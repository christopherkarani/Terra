import Testing
@testable import TerraCore

@Suite("Internal constants string values")
struct TerraInternalConstantsTests {
  @Test("SpanNames have expected string values")
  func spanNames_expectedValues() {
    #expect(Terra.SpanNames.inference == "gen_ai.inference")
    #expect(Terra.SpanNames.embedding == "gen_ai.embeddings")
    #expect(Terra.SpanNames.agentInvocation == "gen_ai.agent")
    #expect(Terra.SpanNames.toolExecution == "gen_ai.tool")
    #expect(Terra.SpanNames.safetyCheck == "terra.safety_check")
  }

  @Test("isTerraSpanName recognises all span names")
  func isTerraSpanName_recognisesAll() {
    #expect(Terra.SpanNames.isTerraSpanName("gen_ai.inference"))
    #expect(Terra.SpanNames.isTerraSpanName("gen_ai.embeddings"))
    #expect(Terra.SpanNames.isTerraSpanName("gen_ai.agent"))
    #expect(Terra.SpanNames.isTerraSpanName("gen_ai.tool"))
    #expect(Terra.SpanNames.isTerraSpanName("terra.safety_check"))
    #expect(!Terra.SpanNames.isTerraSpanName("unknown.span"))
  }

  @Test("MetricNames have expected string values")
  func metricNames_expectedValues() {
    #expect(Terra.MetricNames.inferenceCount == "terra.inference.count")
    #expect(Terra.MetricNames.inferenceDurationMs == "terra.inference.duration_ms")
  }

  @Test("OperationName raw values match semantic conventions")
  func operationName_rawValues() {
    #expect(Terra.OperationName.inference.rawValue == "inference")
    #expect(Terra.OperationName.embeddings.rawValue == "embeddings")
    #expect(Terra.OperationName.invokeAgent.rawValue == "invoke_agent")
    #expect(Terra.OperationName.executeTool.rawValue == "execute_tool")
    #expect(Terra.OperationName.safetyCheck.rawValue == "safety_check")
  }
}
