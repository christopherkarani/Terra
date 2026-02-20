import Foundation

extension Terra {
  public enum SemanticVersion: String, Sendable, Hashable, CaseIterable {
    case v1 = "v1"
  }

  public enum RuntimeKind: String, Sendable, Hashable, CaseIterable {
    case coreML = "coreml"
    case foundationModels = "foundation_models"
    case mlx = "mlx"
    case ollama = "ollama"
    case lmStudio = "lm_studio"
    case llamaCpp = "llama_cpp"
    case openClawGateway = "openclaw_gateway"
    case httpAPI = "http_api"

    static func fromContractValue(_ value: String) -> RuntimeKind? {
      let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      switch normalized {
      case "coreml":
        return .coreML
      case "foundation_models", "foundation-models", "foundation models":
        return .foundationModels
      case "mlx":
        return .mlx
      case "ollama":
        return .ollama
      case "lm_studio", "lmstudio", "lm-studio":
        return .lmStudio
      case "llama_cpp", "llamacpp", "llama-cpp":
        return .llamaCpp
      case "openclaw_gateway", "openclaw-gateway", "openclaw gateway", "gateway":
        return .openClawGateway
      case "http_api", "httpapi", "http":
        return .httpAPI
      default:
        return nil
      }
    }
  }

  public enum SpanNames {
    public static let modelLoad = "terra.model.load"
    public static let inference = "terra.inference"
    public static let embedding = "terra.embeddings"
    public static let agentInvocation = "terra.agent"
    public static let toolExecution = "terra.tool"
    public static let safetyCheck = "terra.safety_check"
    public static let stagePromptEval = "terra.stage.prompt_eval"
    public static let stageDecode = "terra.stage.decode"
    public static let streamLifecycle = "terra.stream.lifecycle"

    static func isTerraSpanName(_ name: String) -> Bool {
      switch name {
      case modelLoad, inference, embedding, agentInvocation, toolExecution, safetyCheck, stagePromptEval, stageDecode, streamLifecycle:
        return true
      default:
        return false
      }
    }
  }

  public enum MetricNames {
    public static let inferenceCount = "terra.inference.count"
    public static let inferenceDurationMs = "terra.inference.duration_ms"
    public static let recommendationCount = "terra.recommendation.count"
    public static let anomalyCount = "terra.anomaly.count"
    public static let stalledTokenCount = "terra.stall.count"
  }

  public enum OperationName: String, Sendable {
    case inference
    case chat
    case textCompletion = "text_completion"
    case embeddings
    case invokeAgent = "invoke_agent"
    case executeTool = "execute_tool"
    case safetyCheck = "safety_check"
    case modelLoad = "model_load"
    case promptEval = "prompt_eval"
    case decode
    case streamLifecycle = "stream_lifecycle"
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
      public static let semanticVersion = "terra.semantic.version"
      public static let schemaFamily = "terra.schema.family"
      public static let requestID = "terra.request.id"
      public static let sessionID = "terra.session.id"
      public static let modelFingerprint = "terra.model.fingerprint"
      public static let modelFingerprintSynthesis = "terra.model.fingerprint.synthesized"
      public static let runtimeSynthesis = "terra.runtime.synthesized"
      public static let availability = "terra.availability"
      public static let runtimeConfidence = "terra.runtime.confidence"

      public static let contentPolicy = "terra.privacy.content_policy"
      public static let contentRedaction = "terra.privacy.content_redaction"
      public static let anonymizationKeyID = "terra.anonymization.key_id"

      public static let promptLength = "terra.prompt.length"
      public static let promptSHA256 = "terra.prompt.sha256"

      public static let embeddingInputCount = "terra.embeddings.input.count"

      public static let safetyCheckName = "terra.safety.check.name"
      public static let safetySubjectLength = "terra.safety.subject.length"
      public static let safetySubjectSHA256 = "terra.safety.subject.sha256"

      /// Marks spans created by auto-instrumentation (vs. manual `withInferenceSpan`).
      public static let autoInstrumented = "terra.auto_instrumented"

      /// Runtime that produced the span (e.g. "coreml", "foundation_models", "mlx", "http_api").
      public static let runtime = "terra.runtime"
      public static let runtimeClass = "terra.runtime.class"
      public static let runtimeCapability = "terra.runtime.capability"

      /// True when a span came through the OpenClaw gateway integration path.
      public static let openClawGateway = "terra.openclaw.gateway"

      /// OpenClaw integration mode used when the span was recorded.
      public static let openClawMode = "terra.openclaw.mode"

      /// Foundation Models context window size when surfaced by the runtime.
      public static let foundationModelsContextWindowTokens = "terra.foundation_models.context_window_tokens"

      // MARK: Semantic timing attributes
      public static let latencyTTFTMs = "terra.latency.ttft_ms"
      public static let latencyEndToEndMs = "terra.latency.e2e_ms"
      public static let latencyPromptEvalMs = "terra.latency.prompt_eval_ms"
      public static let latencyModelLoadMs = "terra.latency.model_load_ms"
      public static let latencyDecodeMs = "terra.latency.decode_ms"
      public static let latencyTailP95Ms = "terra.latency.tail_p95_ms"
      public static let latencyTailP99Ms = "terra.latency.tail_p99_ms"
      public static let stageName = "terra.stage.name"
      public static let stageTokenCount = "terra.stage.token_count"

      // MARK: Streaming inference attributes
      public static let streamTimeToFirstTokenMs = "terra.stream.time_to_first_token_ms"
      public static let streamTokensPerSecond = "terra.stream.tokens_per_second"
      public static let streamOutputTokens = "terra.stream.output_tokens"
      public static let streamChunkCount = "terra.stream.chunk_count"
      public static let streamFirstTokenEvent = "terra.first_token"
      public static let streamLifecycleEvent = "terra.token.lifecycle"
      public static let streamTokenIndex = "terra.token.index"
      public static let streamTokenGapMs = "terra.token.gap_ms"
      public static let streamTokenStage = "terra.token.stage"
      public static let streamTokenLogProb = "terra.token.logprob"

      // MARK: Stall detection
      public static let stalledTokenEvent = "terra.anomaly.stalled_token"
      public static let stalledTokenGapMs = "terra.stall.gap_ms"
      public static let stalledTokenThresholdMs = "terra.stall.threshold_ms"
      public static let stalledTokenBaselineP95Ms = "terra.stall.baseline_p95_ms"

      // MARK: Runtime diagnostics
      public static let thermalState = "terra.process.thermal_state"
      public static let processMemoryResidentDeltaMB = "terra.process.memory_resident_delta_mb"
      public static let processMemoryPeakMB = "terra.process.memory_peak_mb"
      public static let powerState = "terra.hw.power_state"
      public static let memoryPressure = "terra.hw.memory_pressure"
      public static let processRSSMB = "terra.hw.rss_mb"
      public static let memoryChurnMB = "terra.hw.memory_churn_mb"
      public static let gpuOccupancyPct = "terra.hw.gpu_occupancy_pct"
      public static let aneUtilizationPct = "terra.hw.ane_utilization_pct"

      // MARK: Recommendations and anomalies
      public static let recommendationEvent = "terra.recommendation"
      public static let recommendationKind = "terra.recommendation.kind"
      public static let recommendationID = "terra.recommendation.id"
      public static let recommendationConfidence = "terra.recommendation.confidence"
      public static let recommendationAction = "terra.recommendation.action"
      public static let recommendationReason = "terra.recommendation.reason"
      public static let anomalyKind = "terra.anomaly.kind"
      public static let anomalyScore = "terra.anomaly.score"
      public static let anomalyBaselineKey = "terra.anomaly.baseline_key"

      // MARK: Compliance and control
      public static let policyBlocked = "terra.policy.blocked"
      public static let policyReason = "terra.policy.reason"
      public static let controlLoopMode = "terra.control_loop.mode"
      public static let eventAggregationLevel = "terra.event.aggregation_level"
    }
  }
}
