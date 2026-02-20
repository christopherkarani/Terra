import Foundation
import XCTest
@testable import TerraHTTPInstrument

final class AIResponseStreamParserTests: XCTestCase {
  func testParseOllamaNDJSONCapturesStagesAndStall() {
    let body = [
      #"""
      {"model":"qwen2","created_at":"2024-01-01T00:00:00.000Z","response":"H","done":false}
      {"model":"qwen2","created_at":"2024-01-01T00:00:00.500Z","response":"i","done":false}
      {"model":"qwen2","created_at":"2024-01-01T00:00:01.000Z","done":true,"prompt_eval_count":14,"eval_count":2,"prompt_eval_duration":1500000000,"eval_duration":2500000000,"load_duration":800000}
      """#
    ].joined(separator: "\n").data(using: .utf8)!

    let parsed = AIResponseStreamParser.parse(
      data: body,
      runtime: .ollama,
      requestModel: "qwen2"
    )

    XCTAssertNotNil(parsed)
    guard let parsed else { return }
    XCTAssertEqual(parsed.response.model, "qwen2")
    XCTAssertEqual(parsed.stream.promptEvalTokenCount, 14)
    XCTAssertEqual(parsed.stream.decodeTokenCount, 2)
    XCTAssertEqual(parsed.stream.streamChunkCount, 2)
    XCTAssertNotNil(parsed.stream.events.first(where: { $0.name == "terra.stream.lifecycle" }))
    XCTAssertNotNil(parsed.stream.events.first(where: { $0.name == "terra.anomaly.stalled_token" }))
    XCTAssertEqual(parsed.stream.streamTTFMS, 1500.0)
    XCTAssertEqual(parsed.stream.loadDurationMs, 800.0)
    XCTAssertNotNil(parsed.stream.events.first(where: { $0.name == "terra.model.load" }))
  }

  func testParseLMStudioSSECapturesLifecycleAndUsage() {
    let body = [
      "event: model_load.started",
      #"data: {"created":1704067201.0,"event":"model_load.started","model":"llama"}"#,
      "event: prompt_processing.started",
      #"data: {"created":1704067201.2,"event":"prompt_processing.started","model":"llama"}"#,
      "event: chat.request",
      #"data: {"created":1704067201.3,"model":"llama","choices":[{"delta":{"content":"hello "}}]}"#,
      "event: chat.response",
      #"data: {"created":1704067201.4,"model":"llama","choices":[{"delta":{"content":"world","logprob":-0.13}}], "usage":{"prompt_tokens":22,"completion_tokens":2}}"#,
      "event: chat.done",
      "data: [DONE]",
    ].joined(separator: "\n").data(using: .utf8)!

    let parsed = AIResponseStreamParser.parse(
      data: body,
      runtime: .lmStudio,
      requestModel: "llama"
    )

    XCTAssertNotNil(parsed)
    guard let parsed else { return }
    XCTAssertEqual(parsed.response.model, "llama")
    XCTAssertEqual(parsed.stream.promptEvalTokenCount, 22)
    XCTAssertEqual(parsed.stream.decodeTokenCount, 2)
    XCTAssertEqual(parsed.stream.streamChunkCount, 2)
    XCTAssertTrue(parsed.stream.events.contains { $0.name == "terra.stage.prompt_eval" })
    XCTAssertTrue(parsed.stream.events.contains { $0.name == "terra.stream.lifecycle" })
    XCTAssertNotNil(parsed.stream.events.first(where: { $0.name == "terra.stage.decode" }))
  }

  func testMalformedStreamChunksAreRecoveredAndStillParseTokens() {
    let body = [
      "not-json",
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.000Z","response":"A","done":false}"#,
      "still-garbage",
      #"{"model":"qwen2","created_at":"2024-01-01T00:00:00.250Z","done":true}"#,
    ].joined(separator: "\n").data(using: .utf8)!

    let parsed = AIResponseStreamParser.parse(
      data: body,
      runtime: .ollama,
      requestModel: "qwen2"
    )
    XCTAssertNotNil(parsed)
    guard let parsed else { return }
    XCTAssertEqual(parsed.stream.streamChunkCount, 1)
    XCTAssertEqual(parsed.response.model, "qwen2")
  }

  func testParseLMStudioNonSSEWithoutTokensLeavesTTFUnknown() {
    let body = #"""
      {"model":"llama","usage":{"prompt_tokens":22,"completion_tokens":0},"created":1704067201.0}
    """#.data(using: .utf8)!

    let parsed = AIResponseStreamParser.parse(
      data: body,
      runtime: .lmStudio,
      requestModel: "llama"
    )

    XCTAssertNotNil(parsed)
    guard let parsed else { return }
    XCTAssertNil(parsed.stream.streamTTFMS)
    XCTAssertTrue(parsed.stream.events.filter { $0.name == "terra.stream.lifecycle" }.isEmpty)
    XCTAssertEqual(parsed.stream.promptEvalTokenCount, 22)
    XCTAssertEqual(parsed.stream.decodeTokenCount, 0)
  }
}
