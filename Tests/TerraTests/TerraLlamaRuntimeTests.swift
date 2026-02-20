import XCTest
import OpenTelemetrySdk
import TerraLlama
@testable import TerraCore

final class TerraLlamaRuntimeTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    support = nil
    super.tearDown()
  }

  func testLlamaRuntimeUsesCanonicalContractValue() async throws {
    let requestModel = "test-llama.cpp-model"

    await TerraLlama.traced(model: requestModel) { _ in
      // streaming body intentionally empty; runtime contract should be set on span creation.
    }

    let spans = support.finishedSpans()
    let root = try XCTUnwrap(spans.first)
    XCTAssertEqual(
      root.attributes[Terra.Keys.Terra.runtime]?.description,
      Terra.RuntimeKind.llamaCpp.rawValue
    )
  }

  func testCallbackBridgeCorrelatesConcurrentHandlesWithoutCrossTalk() async throws {
    async let first: Void = TerraLlama.withRegisteredScope(model: "llama-handle-a") { handle, _ in
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<24 {
          group.addTask {
            _ = TerraLlama.recordTokenCallback(
              handle: handle,
              tokenIndex: index,
              decodeLatencyMS: 1.0
            )
          }
        }
      }
      _ = TerraLlama.finishCallback(handle: handle)
    }

    async let second: Void = TerraLlama.withRegisteredScope(model: "llama-handle-b") { handle, _ in
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<24 {
          group.addTask {
            _ = TerraLlama.recordTokenCallback(
              handle: handle,
              tokenIndex: 10_000 + index,
              decodeLatencyMS: 1.0
            )
          }
        }
      }
      _ = TerraLlama.finishCallback(handle: handle)
    }

    _ = await (first, second)

    let spans = support.finishedSpans()
    let firstSpan = try XCTUnwrap(span(forModel: "llama-handle-a", in: spans))
    let secondSpan = try XCTUnwrap(span(forModel: "llama-handle-b", in: spans))

    let firstIndices = Set(tokenIndices(in: firstSpan))
    let secondIndices = Set(tokenIndices(in: secondSpan))

    XCTAssertEqual(firstIndices.count, 24)
    XCTAssertEqual(secondIndices.count, 24)
    XCTAssertTrue(firstIndices.allSatisfy { $0 < 10_000 })
    XCTAssertTrue(secondIndices.allSatisfy { $0 >= 10_000 })
  }

  func testStageCallbacksMapToCanonicalLifecycleEventsAndAttributes() async throws {
    let callbackResults = await TerraLlama.withRegisteredScope(model: "llama-stage-mapping") { handle, _ in
      let modelLoadAccepted = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .modelLoad,
        durationMS: 48.0
      )
      let promptAccepted = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .promptEval,
        tokenCount: 32,
        durationMS: 12.5
      )
      let decodeAccepted = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .decode,
        tokenCount: 4,
        durationMS: 8.25
      )
      let streamAccepted = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .streamLifecycle
      )
      let stallAccepted = TerraLlama.recordStallCallback(
        handle: handle,
        gapMS: 77.0,
        thresholdMS: 50.0,
        baselineP95MS: 60.0
      )
      let finishAccepted = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .finish,
        tokenCount: 4
      )
      let postFinishAccepted = TerraLlama.recordTokenCallback(handle: handle, tokenIndex: 99)
      return (
        modelLoadAccepted,
        promptAccepted,
        decodeAccepted,
        streamAccepted,
        stallAccepted,
        finishAccepted,
        postFinishAccepted
      )
    }

    XCTAssertTrue(callbackResults.0)
    XCTAssertTrue(callbackResults.1)
    XCTAssertTrue(callbackResults.2)
    XCTAssertTrue(callbackResults.3)
    XCTAssertTrue(callbackResults.4)
    XCTAssertTrue(callbackResults.5)
    XCTAssertFalse(callbackResults.6)

    let span = try XCTUnwrap(span(forModel: "llama-stage-mapping", in: support.finishedSpans()))
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.latencyModelLoadMs])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.latencyPromptEvalMs])
    XCTAssertNotNil(span.attributes[Terra.Keys.Terra.latencyDecodeMs])

    XCTAssertTrue(
      span.events.contains {
        $0.name == Terra.SpanNames.modelLoad &&
          $0.attributes[Terra.Keys.Terra.stageName]?.description == Terra.OperationName.modelLoad.rawValue
      }
    )
    XCTAssertTrue(
      span.events.contains {
        $0.name == Terra.SpanNames.stageDecode &&
          $0.attributes[Terra.Keys.Terra.stageName]?.description == Terra.InferenceStage.decode.rawValue
      }
    )
    XCTAssertTrue(
      span.events.contains {
        $0.name == Terra.SpanNames.streamLifecycle &&
          $0.attributes[Terra.Keys.Terra.stageName]?.description == Terra.InferenceStage.streamLifecycle.rawValue
      }
    )
    XCTAssertTrue(
      span.events.contains {
        $0.name == Terra.SpanNames.streamLifecycle &&
          $0.attributes[Terra.Keys.Terra.stageName]?.description == "finish"
      }
    )
    XCTAssertTrue(span.events.contains { $0.name == Terra.Keys.Terra.stalledTokenEvent })
  }

  func testTokenLifecycleCallbacksPreserveOrderingAndGapAttribution() async throws {
    await TerraLlama.withRegisteredScope(model: "llama-token-ordering") { handle, _ in
      _ = TerraLlama.recordTokenCallback(
        handle: handle,
        tokenIndex: 0,
        decodeLatencyMS: 2.0,
        logProbability: -0.3
      )
      try? await Task.sleep(nanoseconds: 15_000_000)
      _ = TerraLlama.recordTokenCallback(
        handle: handle,
        tokenIndex: 1,
        decodeLatencyMS: 3.0,
        logProbability: -0.1
      )
      _ = TerraLlama.finishCallback(handle: handle)
    }

    let span = try XCTUnwrap(span(forModel: "llama-token-ordering", in: support.finishedSpans()))
    let lifecycleEvents = span.events
      .filter { $0.name == Terra.Keys.Terra.streamLifecycleEvent }
      .compactMap { event -> (index: Int, gap: Double?)? in
        guard let indexRaw = event.attributes[Terra.Keys.Terra.streamTokenIndex]?.description,
              let index = Int(indexRaw)
        else {
          return nil
        }
        let gap: Double?
        if let gapRaw = event.attributes[Terra.Keys.Terra.streamTokenGapMs]?.description {
          gap = Double(gapRaw)
        } else {
          gap = nil
        }
        return (index: index, gap: gap)
      }
      .sorted(by: { $0.index < $1.index })

    XCTAssertEqual(lifecycleEvents.count, 2)
    XCTAssertEqual(lifecycleEvents.map { $0.index }, [0, 1])
    XCTAssertNil(lifecycleEvents[0].gap)
    XCTAssertNotNil(lifecycleEvents[1].gap)
    XCTAssertGreaterThan(lifecycleEvents[1].gap ?? 0, 0)
  }

  func testUnregisterDropsSubsequentCallbacks() async throws {
    let callbackResults = await TerraLlama.traced(model: "llama-unregister-safety") { scope in
      let handle = TerraLlama.registerStreamingScope(scope)
      let initialAccepted = TerraLlama.recordTokenCallback(handle: handle, tokenIndex: 0)
      TerraLlama.unregisterStreamingScope(handle: handle)
      let tokenAcceptedAfterUnregister = TerraLlama.recordTokenCallback(handle: handle, tokenIndex: 1)
      let stageAcceptedAfterUnregister = TerraLlama.recordStageCallback(
        handle: handle,
        stage: .decode,
        tokenCount: 2,
        durationMS: 1.0
      )
      let stallAcceptedAfterUnregister = TerraLlama.recordStallCallback(
        handle: handle,
        gapMS: 100.0,
        thresholdMS: 50.0
      )
      let finishAcceptedAfterUnregister = TerraLlama.finishCallback(handle: handle)
      return (
        initialAccepted,
        tokenAcceptedAfterUnregister,
        stageAcceptedAfterUnregister,
        stallAcceptedAfterUnregister,
        finishAcceptedAfterUnregister
      )
    }

    XCTAssertTrue(callbackResults.0)
    XCTAssertFalse(callbackResults.1)
    XCTAssertFalse(callbackResults.2)
    XCTAssertFalse(callbackResults.3)
    XCTAssertFalse(callbackResults.4)
  }

  private func span(forModel model: String, in spans: [SpanData]) -> SpanData? {
    spans.first { span in
      span.attributes[Terra.Keys.GenAI.requestModel]?.description == model
    }
  }

  private func tokenIndices(in span: SpanData) -> [Int] {
    span.events.compactMap { event in
      guard event.name == Terra.Keys.Terra.streamLifecycleEvent else { return nil }
      guard let raw = event.attributes[Terra.Keys.Terra.streamTokenIndex]?.description else { return nil }
      return Int(raw)
    }
  }
}
