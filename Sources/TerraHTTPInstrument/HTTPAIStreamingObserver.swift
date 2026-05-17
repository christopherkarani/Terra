import Foundation
import OpenTelemetryApi
import TerraCore

/// Captures streaming-inference summary metrics for HTTP AI requests that
/// flow through `URLSessionInstrumentation` auto-instrumentation.
///
/// SUMMARY-ONLY: upstream `URLSessionInstrumentation` does not expose a
/// per-chunk callback for the completion-handler or async/await code paths,
/// and Terra deliberately does not swizzle `URLSessionDataDelegate` to obtain
/// one (per P0-3 design choice — Approach B). Instead, the streaming response
/// body is delivered as a single buffered `Data` blob via `receivedResponse`,
/// and we derive summary attributes (`terra.stream.completed`, output tokens,
/// chunk count, time-to-first-token) from that blob. Per-chunk metrics
/// require manual `Terra.stream { span in span.chunk(...) }` usage.
///
/// `recordChunk(for:data:)` remains internal so existing tests that exercise
/// the streaming-error path can drive the observer directly. External callers
/// must use the manual `Terra.stream` API for true per-chunk telemetry.
final class HTTPAIStreamingObserver: @unchecked Sendable {
  static let shared = HTTPAIStreamingObserver()

  private let lock = NSLock()
  private var states: [String: State] = [:]
  private let maxActiveStreamStates = 1_024

  private let streamSpanIDProperty = "io.opentelemetry.terra.http.span_id"
  private let streamEnabledProperty = "io.opentelemetry.terra.http.stream_enabled"

  private struct State {
    let span: any Span
    let request: URLRequest
    let startedAt: ContinuousClock.Instant
    var firstChunkAt: ContinuousClock.Instant?
    var chunkCount = 0
    var outputTokens: Int?
  }

  /// Marks the streaming observer as ready. Retained for source compatibility
  /// with call sites that gate streaming registration on `installIfNeeded()`.
  /// SUMMARY-ONLY mode (Approach B): this is intentionally a no-op flag
  /// setter — no `URLSessionDataDelegate` swizzle is performed. Per-chunk
  /// timing requires manual `Terra.stream { ... }` usage.
  func installIfNeeded() {
    // Intentionally empty — see SUMMARY-ONLY note on the type.
  }

  func attachProperties(to request: inout URLRequest, span: (any Span)?, parsedRequest: ParsedRequest?) {
    guard let span, parsedRequest?.stream == true else { return }
    let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
    URLProtocol.setProperty(span.context.spanId.hexString, forKey: streamSpanIDProperty, in: mutableRequest)
    URLProtocol.setProperty(true, forKey: streamEnabledProperty, in: mutableRequest)
    request = mutableRequest as URLRequest
  }

  func register(request: URLRequest, span: any Span, parsedRequest: ParsedRequest?) {
    guard parsedRequest?.stream == true, let spanID = spanID(for: request) else { return }
    lock.lock()
    evictOldestStateIfNeededLocked(inserting: spanID)
    states[spanID] = State(span: span, request: request, startedAt: .now)
    lock.unlock()
  }

  /// Returns the registered `URLRequest` for an active streaming span, or
  /// nil if the span is not a registered streaming request. Used by the
  /// auto-instrumentation `receivedResponse` callback to associate the
  /// buffered SSE body with the correct request for chunk extraction.
  func registeredRequest(forSpan span: any Span) -> URLRequest? {
    let spanID = span.context.spanId.hexString
    lock.lock()
    defer { lock.unlock() }
    return states[spanID]?.request
  }

  /// Records a single streaming chunk for an active request.
  /// INTERNAL ONLY: kept so the streaming-error test path can simulate a
  /// pre-error chunk and verify `terra.stream.chunk_count`, but NOT invoked
  /// from the auto-instrumented production code path. Auto-instrumentation
  /// uses `recordCompletedStreamBody(for:data:)` to emit summary metrics
  /// after the full SSE body is buffered by URLSession.
  func recordChunk(for request: URLRequest?, data: Data) {
    guard let request, isStreaming(request: request), let spanID = spanID(for: request) else { return }

    let now = ContinuousClock.now
    let timestamp = Date()
    var span: (any Span)?
    var chunkIndex = 0
    var shouldEmitFirstToken = false
    var outputTokens: Int?

    lock.lock()
    if var state = states[spanID] {
      state.chunkCount += 1
      chunkIndex = state.chunkCount
      if state.firstChunkAt == nil {
        state.firstChunkAt = now
        shouldEmitFirstToken = true
      }
      if let parsedOutputTokens = AIStreamingChunkParser.outputTokens(from: data) {
        state.outputTokens = parsedOutputTokens
      }
      outputTokens = state.outputTokens
      span = state.span
      states[spanID] = state
    }
    lock.unlock()

    guard let span else { return }
    if shouldEmitFirstToken {
      span.addEvent(name: Terra.Keys.Terra.streamFirstTokenEvent, timestamp: timestamp)
    }

    var attributes: [String: AttributeValue] = [
      "chunk_index": .int(chunkIndex),
    ]
    if let outputTokens {
      attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(outputTokens)
    }
    span.addEvent(name: "stream.chunk", attributes: attributes, timestamp: timestamp)
  }

  /// Auto-instrumentation entry point for SUMMARY-ONLY streaming metrics.
  ///
  /// Called from `HTTPAIInstrumentation.receivedResponse` once the entire
  /// streamed SSE body has been buffered by `URLSessionInstrumentation`. We
  /// synthesize a single first-token event (timed at receipt) and derive
  /// the SSE-line count plus output-token count from the buffered payload.
  /// The actual `finish` call happens immediately after, on the same span,
  /// populating chunk count, output tokens, and `terra.stream.completed`.
  ///
  /// The `chunkCount` reported reflects the number of `data: ...` lines in
  /// the buffered body — a useful approximation for downstream dashboards
  /// even though it does not give true per-chunk timing.
  func recordCompletedStreamBody(for request: URLRequest?, data: Data) {
    guard let request, isStreaming(request: request), let spanID = spanID(for: request) else { return }

    let now = ContinuousClock.now
    let timestamp = Date()
    let lineCount = countSSEChunks(in: data)
    let parsedOutputTokens = AIStreamingChunkParser.outputTokens(from: data)
    var span: (any Span)?
    var shouldEmitFirstToken = false

    lock.lock()
    if var state = states[spanID] {
      if state.firstChunkAt == nil {
        state.firstChunkAt = now
        shouldEmitFirstToken = true
      }
      // Use the SSE-line count rather than a single increment so summary
      // dashboards see a representative value even without per-chunk timing.
      state.chunkCount = max(state.chunkCount, lineCount)
      if let parsedOutputTokens {
        state.outputTokens = parsedOutputTokens
      }
      span = state.span
      states[spanID] = state
    }
    lock.unlock()

    guard let span, shouldEmitFirstToken else { return }
    span.addEvent(name: Terra.Keys.Terra.streamFirstTokenEvent, timestamp: timestamp)
  }

  func finish(span: any Span, parsedResponse: ParsedResponse?) {
    let spanID = span.context.spanId.hexString
    finish(spanID: spanID, parsedResponse: parsedResponse, error: nil)
  }

  func finishWithError(span: any Span, error: Error? = nil) {
    let spanID = span.context.spanId.hexString
    finish(spanID: spanID, parsedResponse: nil, error: error)
  }

  func finishWithError(request: URLRequest?, error: Error? = nil) {
    guard let request, let spanID = spanID(for: request) else { return }
    finish(spanID: spanID, parsedResponse: nil, error: error)
  }

  private func finish(spanID: String, parsedResponse: ParsedResponse?, error: Error?) {
    let now = ContinuousClock.now
    var state: State?

    lock.lock()
    state = states.removeValue(forKey: spanID)
    lock.unlock()

    guard let state else { return }

    var attributes: [String: AttributeValue] = [
      Terra.Keys.Terra.streamChunkCount: .int(state.chunkCount),
    ]
    if let error {
      let errorType = Terra.sanitizedErrorType(error)
      attributes["terra.stream.completed"] = .bool(false)
      attributes["error.type"] = .string(errorType)
      state.span.status = .error(description: errorType)
    } else {
      // P0-3 fix: success path was missing this attribute, so dashboards
      // could not tell completion from premature termination.
      attributes["terra.stream.completed"] = .bool(true)
    }

    let resolvedOutputTokens = parsedResponse?.outputTokens ?? state.outputTokens
    if let resolvedOutputTokens {
      attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(resolvedOutputTokens)
      attributes[Terra.Keys.Terra.streamOutputTokens] = .int(resolvedOutputTokens)
    }
    if let firstChunkAt = state.firstChunkAt {
      let ttft = durationToMs(state.startedAt.duration(to: firstChunkAt))
      attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs] = .double(ttft)
      if let resolvedOutputTokens {
        let generationDuration = firstChunkAt.duration(to: now)
        let generationSeconds = max(durationToSeconds(generationDuration), 0.000_001)
        attributes[Terra.Keys.Terra.streamTokensPerSecond] = .double(Double(resolvedOutputTokens) / generationSeconds)
      }
    }

    state.span.setAttributes(attributes)
    if let error {
      state.span.addEvent(
        name: "stream.error",
        attributes: [
          "error.type": .string(Terra.sanitizedErrorType(error))
        ]
      )
    }
  }

  func reset() {
    lock.lock()
    states.removeAll()
    lock.unlock()
  }

  private func spanID(for request: URLRequest) -> String? {
    URLProtocol.property(forKey: streamSpanIDProperty, in: request) as? String
  }

  private func evictOldestStateIfNeededLocked(inserting spanID: String) {
    guard states[spanID] == nil, states.count >= maxActiveStreamStates else { return }
    guard let oldest = states.min(by: { $0.value.startedAt < $1.value.startedAt })?.key else { return }
    states.removeValue(forKey: oldest)
  }

  private func isStreaming(request: URLRequest) -> Bool {
    (URLProtocol.property(forKey: streamEnabledProperty, in: request) as? Bool) == true
  }

  private func countSSEChunks(in data: Data) -> Int {
    guard let text = String(data: data, encoding: .utf8) else { return 0 }
    var count = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("data:") else { continue }
      let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
      guard payload != "[DONE]", !payload.isEmpty else { continue }
      count += 1
    }
    return count
  }

  private func durationToMs(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
  }

  private func durationToSeconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
  }
}
