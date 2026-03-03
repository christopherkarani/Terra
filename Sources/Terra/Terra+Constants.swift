import Foundation

extension Terra {
  enum SpanNames {
    static let inference = "gen_ai.inference"
    static let embedding = "gen_ai.embeddings"
    static let agentInvocation = "gen_ai.agent"
    static let toolExecution = "gen_ai.tool"
    static let safetyCheck = "terra.safety_check"

    static func isTerraSpanName(_ name: String) -> Bool {
      switch name {
      case inference, embedding, agentInvocation, toolExecution, safetyCheck:
        return true
      default:
        return false
      }
    }
  }

  enum MetricNames {
    static let inferenceCount = "terra.inference.count"
    static let inferenceDurationMs = "terra.inference.duration_ms"
  }

  enum OperationName: String, Sendable {
    case inference
    case embeddings
    case invokeAgent = "invoke_agent"
    case executeTool = "execute_tool"
    case safetyCheck = "safety_check"
  }

  public enum Keys {
    public enum GenAI {
      public static let operationName = "gen_ai.operation.name"

      /// OTel standard key for the requested model.
      public static let requestModel = "gen_ai.request.model"

      /// Legacy alias — use `requestModel` for new code.
      @available(*, deprecated, renamed: "requestModel")
      public static let model = "gen_ai.model"

      // MARK: Request attributes
      public static let requestMaxTokens = "gen_ai.request.max_tokens"
      public static let requestTemperature = "gen_ai.request.temperature"
      public static let requestStream = "gen_ai.request.stream"

      // MARK: Response / usage attributes (OTel standard)
      public static let usageInputTokens = "gen_ai.usage.input_tokens"
      public static let usageOutputTokens = "gen_ai.usage.output_tokens"
      public static let responseModel = "gen_ai.response.model"

      // MARK: Provider
      public static let providerName = "gen_ai.provider.name"

      // MARK: Agent attributes
      public static let agentName = "gen_ai.agent.name"
      public static let agentID = "gen_ai.agent.id"

      // MARK: Tool attributes
      public static let toolName = "gen_ai.tool.name"
      public static let toolType = "gen_ai.tool.type"
      public static let toolCallID = "gen_ai.tool.call.id"
    }

    public enum Terra {
      public static let contentPolicy = "terra.privacy.content_policy"
      public static let contentRedaction = "terra.privacy.content_redaction"

      public static let promptLength = "terra.prompt.length"
      public static let promptHMACSHA256 = "terra.prompt.hmac_sha256"
      /// Legacy compatibility attribute during migration to keyed digests.
      public static let promptSHA256 = "terra.prompt.sha256"

      public static let embeddingInputCount = "terra.embeddings.input.count"

      public static let safetyCheckName = "terra.safety.check.name"
      public static let safetySubjectLength = "terra.safety.subject.length"
      public static let safetySubjectHMACSHA256 = "terra.safety.subject.hmac_sha256"
      /// Legacy compatibility attribute during migration to keyed digests.
      public static let safetySubjectSHA256 = "terra.safety.subject.sha256"
      public static let anonymizationKeyID = "terra.anonymization.key_id"

      /// Marks spans created by auto-instrumentation (vs. manual `withInferenceSpan`).
      public static let autoInstrumented = "terra.auto_instrumented"

      /// Runtime that produced the span (e.g. "coreml", "foundation_models", "mlx", "http_api").
      public static let runtime = "terra.runtime"

      /// True when a span came through the OpenClaw gateway integration path.
      public static let openClawGateway = "terra.openclaw.gateway"

      /// OpenClaw integration mode used when the span was recorded.
      public static let openClawMode = "terra.openclaw.mode"

      // MARK: Streaming inference attributes
      public static let streamTimeToFirstTokenMs = "terra.stream.time_to_first_token_ms"
      public static let streamTokensPerSecond = "terra.stream.tokens_per_second"
      public static let streamOutputTokens = "terra.stream.output_tokens"
      public static let streamChunkCount = "terra.stream.chunk_count"
      public static let streamFirstTokenEvent = "terra.first_token"

      // MARK: Runtime diagnostics
      public static let thermalState = "terra.process.thermal_state"
      public static let processMemoryResidentDeltaMB = "process.memory.resident_delta_mb"
      public static let processMemoryPeakMB = "process.memory.peak_mb"
    }
  }
}
