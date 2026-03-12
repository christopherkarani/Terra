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

  package enum Keys {
    package enum GenAI {
      package static let operationName = "gen_ai.operation.name"

      /// OTel standard key for the requested model.
      package static let requestModel = "gen_ai.request.model"

      /// Legacy alias — use `requestModel` for new code.
      @available(*, deprecated, renamed: "requestModel")
      package static let model = "gen_ai.model"

      // MARK: Request attributes
      package static let requestMaxTokens = "gen_ai.request.max_tokens"
      package static let requestTemperature = "gen_ai.request.temperature"
      package static let requestStream = "gen_ai.request.stream"

      // MARK: Response / usage attributes (OTel standard)
      package static let usageInputTokens = "gen_ai.usage.input_tokens"
      package static let usageOutputTokens = "gen_ai.usage.output_tokens"
      package static let responseModel = "gen_ai.response.model"

      // MARK: Provider
      package static let providerName = "gen_ai.provider.name"

      // MARK: Agent attributes
      package static let agentName = "gen_ai.agent.name"
      package static let agentID = "gen_ai.agent.id"

      // MARK: Tool attributes
      package static let toolName = "gen_ai.tool.name"
      package static let toolType = "gen_ai.tool.type"
      package static let toolCallID = "gen_ai.tool.call.id"
    }

    package enum Terra {
      package static let contentPolicy = "terra.privacy.content_policy"
      package static let contentRedaction = "terra.privacy.content_redaction"

      package static let promptLength = "terra.prompt.length"
      package static let promptHMACSHA256 = "terra.prompt.hmac_sha256"
      /// Legacy compatibility attribute during migration to keyed digests.
      package static let promptSHA256 = "terra.prompt.sha256"

      package static let embeddingInputCount = "terra.embeddings.input.count"

      package static let safetyCheckName = "terra.safety.check.name"
      package static let safetySubjectLength = "terra.safety.subject.length"
      package static let safetySubjectHMACSHA256 = "terra.safety.subject.hmac_sha256"
      /// Legacy compatibility attribute during migration to keyed digests.
      package static let safetySubjectSHA256 = "terra.safety.subject.sha256"
      package static let anonymizationKeyID = "terra.anonymization.key_id"

      /// Marks spans created by auto-instrumentation (vs. manual `withInferenceSpan`).
      package static let autoInstrumented = "terra.auto_instrumented"

      /// Runtime that produced the span (e.g. "coreml", "foundation_models", "mlx", "http_api").
      package static let runtime = "terra.runtime"

      /// True when a span came through the OpenClaw gateway integration path.
      package static let openClawGateway = "terra.openclaw.gateway"

      /// OpenClaw integration mode used when the span was recorded.
      package static let openClawMode = "terra.openclaw.mode"

      // MARK: Streaming inference attributes
      package static let streamTimeToFirstTokenMs = "terra.stream.time_to_first_token_ms"
      package static let streamTokensPerSecond = "terra.stream.tokens_per_second"
      package static let streamOutputTokens = "terra.stream.output_tokens"
      package static let streamChunkCount = "terra.stream.chunk_count"
      package static let streamFirstTokenEvent = "terra.first_token"

      // MARK: Runtime diagnostics
      package static let thermalState = "terra.process.thermal_state"
      package static let processMemoryResidentDeltaMB = "process.memory.resident_delta_mb"
      package static let processMemoryPeakMB = "process.memory.peak_mb"

      // MARK: Execution route diagnostics
      package static let execRouteRequested = "terra.exec.route.requested"
      package static let execRouteObserved = "terra.exec.route.observed"
      package static let execRouteEstimatedPrimary = "terra.exec.route.estimated_primary"
      package static let execRouteSupported = "terra.exec.route.supported"
      package static let execRouteCaptureMode = "terra.exec.route.capture_mode"
      package static let execRouteConfidence = "terra.exec.route.confidence"
    }
  }
}
