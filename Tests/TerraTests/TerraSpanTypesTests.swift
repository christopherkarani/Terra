import XCTest
@testable import TerraCore

final class TerraSpanTypesTests: XCTestCase {
  private var support: TerraTestSupport!

  override func setUp() {
    super.setUp()
    support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))
  }

  override func tearDown() {
    support.reset()
    super.tearDown()
  }

  func testWithAgentInvocationSpan_setsExpectedAttributes() async throws {
    let agent = Terra.AgentRequest(name: "planner", id: "agent-1")
    await Terra.withAgentInvocationSpan(agent: agent) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.name, Terra.SpanNames.agentInvocation)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.agentName]?.description, "planner")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.agentID]?.description, "agent-1")
  }

  func testWithToolExecutionSpan_setsExpectedAttributes() async throws {
    await Terra.withToolExecutionSpan(
      tool: .init(name: "search", callID: "call-123", type: "http")
    ) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.name, Terra.SpanNames.toolExecution)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.toolName]?.description, "search")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.toolCallID]?.description, "call-123")
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.toolType]?.description, "http")
  }

  func testWithEmbeddingSpan_setsExpectedAttributes() async throws {
    await Terra.withEmbeddingSpan(.init(model: "embed-model", inputCount: 3)) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.name, Terra.SpanNames.embedding)
    XCTAssertEqual(span.attributes[Terra.Keys.GenAI.requestModel]?.description, "embed-model")
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.embeddingInputCount]?.description, "3")
  }

  func testWithSafetyCheckSpan_setsExpectedAttributes() async throws {
    await Terra.withSafetyCheckSpan(.init(name: "toxicity", subject: "input")) { _ in }

    let span = try XCTUnwrap(support.finishedSpans().first)
    XCTAssertEqual(span.name, Terra.SpanNames.safetyCheck)
    XCTAssertEqual(span.attributes[Terra.Keys.Terra.safetyCheckName]?.description, "toxicity")
  }
}
