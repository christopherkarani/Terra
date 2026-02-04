import Foundation

extension Terra {
  public enum SpanNames {
    public static let inference = "gen_ai.inference"
    public static let embedding = "gen_ai.embeddings"
    public static let agentInvocation = "gen_ai.agent"
    public static let toolExecution = "gen_ai.tool"
    public static let safetyCheck = "terra.safety_check"

    static func isTerraSpanName(_ name: String) -> Bool {
      switch name {
      case inference, embedding, agentInvocation, toolExecution, safetyCheck:
        return true
      default:
        return false
      }
    }
  }

  public enum MetricNames {
    public static let inferenceCount = "terra.inference.count"
    public static let inferenceDurationMs = "terra.inference.duration_ms"
  }

  public enum OperationName: String, Sendable {
    case inference
    case embeddings
    case invokeAgent = "invoke_agent"
    case executeTool = "execute_tool"
    case safetyCheck = "safety_check"
  }

  public enum Keys {
    public enum GenAI {
      public static let operationName = "gen_ai.operation.name"
      public static let model = "gen_ai.model"

      public static let requestMaxTokens = "gen_ai.request.max_tokens"
      public static let requestTemperature = "gen_ai.request.temperature"
      public static let requestStream = "gen_ai.request.stream"

      public static let agentName = "gen_ai.agent.name"
      public static let agentID = "gen_ai.agent.id"

      public static let toolName = "gen_ai.tool.name"
      public static let toolType = "gen_ai.tool.type"
      public static let toolCallID = "gen_ai.tool.call.id"
    }

    public enum Terra {
      public static let contentPolicy = "terra.privacy.content_policy"
      public static let contentRedaction = "terra.privacy.content_redaction"

      public static let promptLength = "terra.prompt.length"
      public static let promptSHA256 = "terra.prompt.sha256"

      public static let embeddingInputCount = "terra.embeddings.input.count"

      public static let safetyCheckName = "terra.safety.check.name"
      public static let safetySubjectLength = "terra.safety.subject.length"
      public static let safetySubjectSHA256 = "terra.safety.subject.sha256"
    }
  }
}
