import Foundation
import OpenTelemetryApi
import TerraCore

enum AITelemetryRuntime: String {
  case unknown
  case ollama
  case lmStudio
}

struct ParsedStreamTelemetry {
  struct Event {
    let name: String
    let timestamp: Date
    let attributes: [String: AttributeValue]
  }

  var model: String?
  var promptEvalTokenCount: Int?
  var decodeTokenCount: Int?
  var promptEvalDurationMs: Double?
  var decodeDurationMs: Double?
  var loadDurationMs: Double?
  var streamTTFMS: Double?
  var streamChunkCount: Int = 0
  var events: [Event] = []
}

struct ParsedResponseAndStream {
  var response: ParsedResponse
  var stream: ParsedStreamTelemetry
}

struct AIResponseStreamParser {
  private enum Constants {
    static let stallThresholdMs = 300.0
    static let maxChunkIndexGap = 1_000_000
  }

  private struct MonotonicTimeline {
    private var anchorWall: Date
    private var anchorClock: ContinuousClock.Instant
    private var lastClock: ContinuousClock.Instant
    private var hasReference = false

    init() {
      let nowWall = Date()
      let nowClock = monotonicNow()
      anchorWall = nowWall
      anchorClock = nowClock
      lastClock = nowClock
    }

    mutating func clock(for wallTime: Date?) -> ContinuousClock.Instant {
      guard let wallTime else {
        let fallback = monotonicNow()
        if fallback > lastClock {
          lastClock = fallback
        }
        return lastClock
      }

      if !hasReference {
        anchorWall = wallTime
        anchorClock = monotonicNow()
        lastClock = anchorClock
        hasReference = true
      }

      let wallDeltaMs = max(0.0, wallTime.timeIntervalSince(anchorWall) * 1000.0)
      let ns = Int64(wallDeltaMs * 1_000_000)
      let projected = anchorClock.advanced(by: .nanoseconds(ns))
      if projected >= lastClock {
        lastClock = projected
      } else {
        lastClock = lastClock + .nanoseconds(0)
      }
      return lastClock
    }

    mutating func gapMs(
      from previous: ContinuousClock.Instant?,
      to current: ContinuousClock.Instant
    ) -> Double? {
      guard let previous else {
        return nil
      }
      return max(0.0, monotonicDurationMS(from: previous, to: current))
    }
  }

  static func parse(
    data: Data,
    runtime: AITelemetryRuntime,
    requestModel: String?
  ) -> ParsedResponseAndStream? {
    guard !data.isEmpty else { return nil }
    guard let decodedText = String(data: data, encoding: .utf8) else { return nil }
    let text = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    let baseResponse = AIResponseParser.parse(data: data).map {
      ParsedResponseAndStream(response: $0, stream: ParsedStreamTelemetry())
    }

    switch runtime {
    case .ollama:
      return parseOllama(text: text, requestModel: requestModel, baseResponse: baseResponse)
    case .lmStudio:
      return parseLMStudio(
        text: text,
        requestModel: requestModel,
        baseResponse: baseResponse,
        isSSE: looksLikeSSE(text: text)
      )
    case .unknown:
      if looksLikeOllama(text: text) {
        return parseOllama(text: text, requestModel: requestModel, baseResponse: baseResponse)
      }
      if looksLikeSSE(text: text) {
        return parseLMStudio(text: text, requestModel: requestModel, baseResponse: baseResponse, isSSE: true)
      }
      return parseLMStudio(
        text: text,
        requestModel: requestModel,
        baseResponse: baseResponse,
        isSSE: false
      )
    }
  }

  private static func looksLikeOllama(text: String) -> Bool {
    guard
      let firstLine = text.split(whereSeparator: \.isNewline).first,
      let frame = parseJSONLine(String(firstLine))
    else {
      return false
    }
    return frame["prompt_eval_count"] != nil
      || frame["eval_count"] != nil
      || frame["load_duration"] != nil
      || frame["prompt_eval_duration"] != nil
      || frame["done"] is Bool
  }

  private static func looksLikeSSE(text: String) -> Bool {
    return text.contains("data:") || text.contains("event:")
  }

  private static func parseOllama(
    text: String,
    requestModel: String?,
    baseResponse: ParsedResponseAndStream?
  ) -> ParsedResponseAndStream? {
    var response = ParsedResponse(inputTokens: nil, outputTokens: nil, model: nil)
    var stream = ParsedStreamTelemetry()
    if let baseResponse {
      response = baseResponse.response
      stream = baseResponse.stream
    }

    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    var tokenIndex = 0
    var timeline = MonotonicTimeline()
    var previousTokenClock: ContinuousClock.Instant?
    var firstFrameClock: ContinuousClock.Instant?
    var firstTokenClock: ContinuousClock.Instant?

    for rawLine in lines {
      guard let frame = parseJSONLine(rawLine) else {
        continue
      }

      let createdAt = parseCreatedAt(from: frame["created_at"]) ?? Date()
      let eventClock = timeline.clock(for: createdAt)
      let responseText = frame["response"] as? String

      if stream.model == nil, let model = frame["model"] as? String {
        stream.model = model
        if response.model == nil {
          response.model = model
        }
      }

      if let done = frame["done"] as? Bool, done {
        let promptCount = asInt(frame["prompt_eval_count"])
        let evalCount = asInt(frame["eval_count"])

        if let promptCount {
          stream.promptEvalTokenCount = promptCount
          response.inputTokens = promptCount
        }
        if let evalCount {
          stream.decodeTokenCount = evalCount
          response.outputTokens = evalCount
        }

        if let promptMs = asDurationMs(from: frame["prompt_eval_duration"]) {
          stream.promptEvalDurationMs = promptMs
          var promptEvalAttributes: [String: AttributeValue] = [
            Terra.Keys.Terra.stageName: .string("prompt_eval"),
            Terra.Keys.Terra.latencyPromptEvalMs: .double(promptMs),
          ]
          if let promptCount {
            promptEvalAttributes[Terra.Keys.Terra.stageTokenCount] = .int(promptCount)
          }
          stream.events.append(
            ParsedStreamTelemetry.Event(
              name: Terra.SpanNames.stagePromptEval,
              timestamp: createdAt,
              attributes: promptEvalAttributes
            )
          )
        }

        if let decodeMs = asDurationMs(from: frame["eval_duration"]) {
          stream.decodeDurationMs = decodeMs
          var decodeAttributes: [String: AttributeValue] = [
            Terra.Keys.Terra.stageName: .string("decode"),
            Terra.Keys.Terra.latencyDecodeMs: .double(decodeMs),
          ]
          if let evalCount {
            decodeAttributes[Terra.Keys.Terra.stageTokenCount] = .int(evalCount)
          }
          stream.events.append(
            ParsedStreamTelemetry.Event(
              name: Terra.SpanNames.stageDecode,
              timestamp: createdAt,
              attributes: decodeAttributes
            )
          )
        }

        if let loadMs = asDurationMs(from: frame["load_duration"]) {
          stream.loadDurationMs = loadMs
          stream.events.append(
            ParsedStreamTelemetry.Event(
              name: Terra.SpanNames.modelLoad,
              timestamp: createdAt,
              attributes: [
                Terra.Keys.Terra.stageName: .string("model_load"),
                Terra.Keys.Terra.latencyModelLoadMs: .double(loadMs),
              ]
            )
          )
        }
      }

      if let responseText, !responseText.isEmpty {
        tokenIndex += 1
        stream.streamChunkCount += 1

        if firstFrameClock == nil {
          firstFrameClock = eventClock
        }
        if firstTokenClock == nil {
          firstTokenClock = eventClock
        }

        if tokenIndex <= Constants.maxChunkIndexGap {
          let gapMs = timeline.gapMs(from: previousTokenClock, to: eventClock)
          let attributes = streamLifecycleAttributes(
            index: tokenIndex,
            stage: "decode",
            logProb: asDouble(frame["logprobs"]),
            gapMs: gapMs
          )
          stream.events.append(
            ParsedStreamTelemetry.Event(
              name: Terra.SpanNames.streamLifecycle,
              timestamp: createdAt,
              attributes: attributes
            )
          )

          if let gapMs, gapMs >= Constants.stallThresholdMs {
            var stalled = baseStallAttributes(index: tokenIndex, gapMs: gapMs, stage: "decode")
            stalled[Terra.Keys.Terra.streamTokenStage] = .string("decode")
            stream.events.append(
              ParsedStreamTelemetry.Event(
                name: Terra.Keys.Terra.stalledTokenEvent,
                timestamp: createdAt,
                attributes: stalled
              )
            )
          }
        }

        previousTokenClock = eventClock
      }
    }

    if stream.streamTTFMS == nil {
      if let promptEval = stream.promptEvalDurationMs {
        stream.streamTTFMS = promptEval
      } else if let decode = stream.decodeDurationMs {
        stream.streamTTFMS = decode
      } else if let firstFrameClock, let firstTokenClock {
        stream.streamTTFMS = monotonicDurationMS(from: firstFrameClock, to: firstTokenClock)
      }
    }

    if response.model == nil {
      response.model = requestModel
    }
    return ParsedResponseAndStream(response: response, stream: stream)
  }

  private static func parseLMStudio(
    text: String,
    requestModel: String?,
    baseResponse: ParsedResponseAndStream?,
    isSSE: Bool
  ) -> ParsedResponseAndStream? {
    var response = ParsedResponse(inputTokens: nil, outputTokens: nil, model: nil)
    var stream = ParsedStreamTelemetry()
    if let baseResponse {
      response = baseResponse.response
      stream = baseResponse.stream
    }

    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    var currentEvent = ""
    var chunkIndex = 0
    var previousChunkClock: ContinuousClock.Instant?
    var firstFrameClock: ContinuousClock.Instant?
    var firstTokenClock: ContinuousClock.Instant?
    var timeline = MonotonicTimeline()

    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else {
        continue
      }

      if isSSE, line.hasPrefix("event:") {
        currentEvent = line
          .replacingOccurrences(of: "event:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        continue
      }

      var payload = line
      if isSSE {
        guard payload.hasPrefix("data:") else {
          continue
        }
        payload = payload
          .replacingOccurrences(of: "data:", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
      guard payload != "[DONE]", let frame = parseJSONLine(payload) else {
        continue
      }

      if stream.model == nil, let model = frame["model"] as? String {
        stream.model = model
        if response.model == nil {
          response.model = model
        }
      }

      if let usage = frame["usage"] as? [String: Any] {
        if let prompt = asInt(usage["prompt_tokens"]) {
          stream.promptEvalTokenCount = prompt
          response.inputTokens = prompt
        }
        if let completion = asInt(usage["completion_tokens"]) {
          stream.decodeTokenCount = completion
          response.outputTokens = completion
        }
      }

      let createdTimestamp = parseCreatedAt(
        from: frame["created"] ?? frame["created_at"]
      ) ?? Date()
      let eventClock = timeline.clock(for: createdTimestamp)
      if firstFrameClock == nil {
        firstFrameClock = eventClock
      }

      if let choices = frame["choices"] as? [[String: Any]],
         let firstChoice = choices.first {
        if let delta = firstChoice["delta"] as? [String: Any],
           let content = delta["content"] as? String,
           !content.isEmpty {
          chunkIndex += 1
          stream.streamChunkCount += 1
          if firstTokenClock == nil {
            firstTokenClock = eventClock
          }

          if chunkIndex <= Constants.maxChunkIndexGap {
            let stage = stageFromLMStudioEvent(currentEvent) ?? "decode"
            let gapMs = timeline.gapMs(from: previousChunkClock, to: eventClock)
            let attributes = streamLifecycleAttributes(
              index: chunkIndex,
              stage: stage,
              logProb: asDouble(delta["logprob"]),
              gapMs: gapMs
            )
            stream.events.append(
              ParsedStreamTelemetry.Event(
                name: Terra.SpanNames.streamLifecycle,
                timestamp: createdTimestamp,
                attributes: attributes
              )
            )

            if let gapMs, gapMs >= Constants.stallThresholdMs {
              let stalled = baseStallAttributes(index: chunkIndex, gapMs: gapMs, stage: stage)
              stream.events.append(
                ParsedStreamTelemetry.Event(
                  name: Terra.Keys.Terra.stalledTokenEvent,
                  timestamp: createdTimestamp,
                  attributes: stalled
                )
              )
            }
          }
        }

        if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" {
          stream.events.append(
            ParsedStreamTelemetry.Event(
              name: Terra.SpanNames.stageDecode,
              timestamp: createdTimestamp,
              attributes: [
                Terra.Keys.Terra.stageName: .string("finish"),
                Terra.Keys.Terra.stageTokenCount: .int(chunkIndex),
              ]
            )
          )
        }
        previousChunkClock = eventClock
      }

      if let stageEventName = stageEventName(currentEvent) {
        stream.events.append(
          ParsedStreamTelemetry.Event(
            name: stageEventName,
            timestamp: createdTimestamp,
            attributes: [
              Terra.Keys.Terra.stageName: .string(stageEventName),
            ]
          )
        )
      }
    }

    if stream.streamTTFMS == nil,
       let firstToken = firstTokenClock,
       let firstFrame = firstFrameClock {
      stream.streamTTFMS = monotonicDurationMS(from: firstFrame, to: firstToken)
    }

    if response.model == nil {
      response.model = requestModel
    }

    return ParsedResponseAndStream(response: response, stream: stream)
  }

  private static func parseCreatedAt(from value: Any?) -> Date? {
    if let raw = value as? String {
      if let parsedISO = parseISO8601Date(raw) {
        return parsedISO
      }
    }
    if let raw = value as? Double {
      return Date(timeIntervalSince1970: raw)
    }
    if let raw = value as? TimeInterval {
      return Date(timeIntervalSince1970: raw)
    }
    if let raw = value as? Int {
      return Date(timeIntervalSince1970: TimeInterval(raw))
    }
    if let raw = value as? Int64 {
      return Date(timeIntervalSince1970: TimeInterval(raw))
    }
    if let raw = value as? UInt64 {
      return Date(timeIntervalSince1970: TimeInterval(raw))
    }
    return nil
  }

  private static func parseJSONLine(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else {
      return nil
    }
    guard let json = try? JSONSerialization.jsonObject(with: data), let dict = json as? [String: Any] else {
      return nil
    }
    return dict
  }

  private static func asInt(_ value: Any?) -> Int? {
    switch value {
    case let rawInt as Int:
      return rawInt
    case let rawDouble as Double:
      return Int(rawDouble)
    case let rawString as String:
      return Int(rawString.trimmingCharacters(in: .whitespacesAndNewlines))
    case let rawNum as NSNumber:
      return rawNum.intValue
    case let rawUInt as UInt64:
      return Int(rawUInt)
    case let rawUInt as UInt:
      return Int(rawUInt)
    default:
      return nil
    }
  }

  private static func asDouble(_ value: Any?) -> Double? {
    switch value {
    case let rawDouble as Double:
      return rawDouble
    case let rawInt as Int:
      return Double(rawInt)
    case let rawString as String:
      return Double(rawString.trimmingCharacters(in: .whitespacesAndNewlines))
    case let rawNum as NSNumber:
      return rawNum.doubleValue
    default:
      return nil
    }
  }

  private static func asDurationMs(from value: Any?) -> Double? {
    guard let raw = asDouble(value) else {
      return nil
    }
    return normalizeDurationMs(raw)
  }

  private static func normalizeDurationMs(_ raw: Double) -> Double {
    if raw >= 1_000_000_000 {
      return raw / 1_000_000
    }
    if raw >= 1_000_000 {
      return raw / 1_000
    }
    if raw >= 1_000 {
      return raw / 1_000
    }
    return raw
  }

  private static func parseISO8601Date(_ value: String) -> Date? {
    if let cached = Iso8601DateFormatterCache.shared.cachedFormatter.date(from: value) {
      return cached
    }

    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = withFractional.date(from: value) {
      Iso8601DateFormatterCache.shared.cache(withFractional)
      return parsed
    }

    let fallback = ISO8601DateFormatter()
    fallback.formatOptions = [.withInternetDateTime]
    if let parsed = fallback.date(from: value) {
      return parsed
    }

    return nil
  }

  private static func streamLifecycleAttributes(
    index: Int,
    stage: String?,
    logProb: Double?,
    gapMs: Double?
  ) -> [String: AttributeValue] {
    var attrs: [String: AttributeValue] = [
      Terra.Keys.Terra.streamTokenIndex: .int(index),
      Terra.Keys.Terra.streamTokenStage: .string(stage ?? "decode"),
    ]
    if let gapMs {
      attrs[Terra.Keys.Terra.streamTokenGapMs] = .double(gapMs)
    }
    if let logProb {
      attrs[Terra.Keys.Terra.streamTokenLogProb] = .double(logProb)
    }
    return attrs
  }

  private static func baseStallAttributes(index: Int, gapMs: Double, stage: String) -> [String: AttributeValue] {
    return [
      Terra.Keys.Terra.stalledTokenGapMs: .double(gapMs),
      Terra.Keys.Terra.stalledTokenThresholdMs: .double(Constants.stallThresholdMs),
      Terra.Keys.Terra.streamTokenIndex: .int(index),
      Terra.Keys.Terra.streamTokenStage: .string(stage),
    ]
  }

  private static func stageFromLMStudioEvent(_ eventName: String) -> String? {
    let normalized = eventName.lowercased()
    if normalized.contains("prompt") {
      return "prompt_eval"
    }
    if normalized.contains("model") || normalized.contains("load") {
      return "model_load"
    }
    if normalized.contains("decode") || normalized.contains("response") || normalized.contains("completion") || normalized.contains("chat") {
      return "decode"
    }
    return nil
  }

  private static func stageEventName(_ eventName: String) -> String? {
    let normalized = eventName.lowercased()
    if normalized.isEmpty {
      return nil
    }
    if normalized.contains("prompt") {
      return Terra.SpanNames.stagePromptEval
    }
    if normalized.contains("decode") || normalized.contains("response") || normalized.contains("completion") || normalized.contains("chat") {
      return Terra.SpanNames.stageDecode
    }
    if normalized.contains("load") || normalized.contains("model") {
      return Terra.SpanNames.modelLoad
    }
    return nil
  }
}

private final class Iso8601DateFormatterCache {
  static let shared = Iso8601DateFormatterCache()
  private(set) var cachedFormatter = ISO8601DateFormatter()

  private init() {
    cachedFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  }

  func cache(_ formatter: ISO8601DateFormatter) {
    cachedFormatter = formatter
  }
}

private func monotonicNow() -> ContinuousClock.Instant {
  ContinuousClock().now
}

private func monotonicDurationMS(
  from start: ContinuousClock.Instant,
  to end: ContinuousClock.Instant
) -> Double {
  let duration = start.duration(to: end)
  let secondsMs = Double(duration.components.seconds) * 1000
  let attosecondsMs = Double(duration.components.attoseconds) / 1_000_000_000_000_000
  return max(0.0, secondsMs + attosecondsMs)
}
