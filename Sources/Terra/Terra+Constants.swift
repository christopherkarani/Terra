import Foundation

extension Terra {
  package enum SpanNames {
    package static let inference = "gen_ai.inference"
    package static let embedding = "gen_ai.embeddings"
    package static let agentInvocation = "gen_ai.agent"
    package static let toolExecution = "gen_ai.tool"
    package static let safetyCheck = "terra.safety_check"
    package static let session = "terra.session"
    package static let modelLoad = "terra.coreml.model_load"

    package static func isTerraSpanName(_ name: String) -> Bool {
      switch name {
      case inference, embedding, agentInvocation, toolExecution, safetyCheck, session, modelLoad:
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
      package static let promptMessageCount = "gen_ai.prompt.message_count"
      package static let promptRole0 = "gen_ai.prompt.role_0"
      package static let promptContent = "gen_ai.prompt.content"

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

      /// Keeps a signal in local persistence without forwarding it to the OTLP exporter.
      package static let exportLocalOnly = "terra.export.local_only"

      // MARK: Streaming inference attributes
      package static let streamTimeToFirstTokenMs = "terra.stream.time_to_first_token_ms"
      package static let streamTokensPerSecond = "terra.stream.tokens_per_second"
      package static let streamOutputTokens = "terra.stream.output_tokens"
      package static let streamChunkCount = "terra.stream.chunk_count"
      package static let streamFirstTokenEvent = "terra.first_token"

      // MARK: Runtime diagnostics
      package static let thermalState = "terra.process.thermal_state"
      package static let gpuOccupancyPct = "terra.hw.gpu_occupancy_pct"
      package static let processMemoryResidentDeltaMB = "process.memory.resident_delta_mb"
      package static let processMemoryPeakMB = "process.memory.peak_mb"
      package static let canonicalProcessMemoryPeakMB = "terra.process.memory_peak_mb"
      package static let canonicalRSSMB = "terra.hw.rss_mb"

      // MARK: Latency attributes
      package static let latencyModelLoadMs = "terra.coreml.load.duration_ms"
      package static let latencyE2EMs = "terra.latency.e2e_ms"

      // MARK: Thermal monitoring (profiled state from ThermalProfile)
      package static let thermalProfileState = "terra.thermal.state"
      package static let thermalPeakState = "terra.thermal.peak_state"
      package static let thermalTimeThrottledS = "terra.thermal.time_throttled_s"

      // MARK: Model size & bandwidth
      package static let modelSizeBytes = "terra.model.size_bytes"
      package static let modelSizeMB = "terra.model.size_mb"
      package static let modelWeightFileCount = "terra.model.weight_file_count"
      package static let modelFormat = "terra.model.format"
      package static let modelBandwidthGBps = "terra.model.bandwidth_gbps"
      package static let modelInferenceTimeMs = "terra.model.inference_time_ms"
      package static let modelComputeDeviceGuess = "terra.model.compute_device_guess"

      // MARK: Espresso log capture (macOS)
      package static let espressoTotalGFlops = "terra.espresso.total_gflops"
      package static let espressoMemoryBoundOps = "terra.espresso.memory_bound_ops"
      package static let espressoComputeBoundOps = "terra.espresso.compute_bound_ops"
      package static let espressoAvgWorkUnitEfficiency = "terra.espresso.avg_work_unit_efficiency"

      // MARK: Power metrics (macOS)
      package static let powerCpuWatts = "terra.power.cpu_watts"
      package static let powerGpuWatts = "terra.power.gpu_watts"
      package static let powerAneWatts = "terra.power.ane_watts"
      package static let powerPackageWatts = "terra.power.package_watts"
      package static let powerSampleCount = "terra.power.sample_count"

      // MARK: Compute plan analysis
      package static let computePlanTotalOps = "terra.compute_plan.total_ops"
      package static let computePlanAneOps = "terra.compute_plan.ane_ops"
      package static let computePlanGpuOps = "terra.compute_plan.gpu_ops"
      package static let computePlanCpuOps = "terra.compute_plan.cpu_ops"
      package static let computePlanAneUtilization = "terra.compute_plan.ane_utilization"
      package static let computePlanDominantDevice = "terra.compute_plan.dominant_device"
      package static let computePlanIsMixedExecution = "terra.compute_plan.is_mixed_execution"

      // MARK: ANE fallback assessment
      package static let aneFallbackLikely = "terra.ane.fallback_likely"
      package static let aneFallbackConfidence = "terra.ane.fallback_confidence"

      // MARK: ANE hardware profiling
      package static let aneHardwareExecutionTimeNs = "terra.ane.hardware_execution_time_ns"
      package static let aneHostOverheadUs = "terra.ane.host_overhead_us"
      package static let canonicalANEHardwareExecutionTimeNs = "terra.hw.ane.hw_execution_time_ns"
      package static let canonicalANEHostOverheadMs = "terra.hw.ane.host_overhead_ms"
      package static let canonicalANEProbeStatus = "terra.hw.ane.probe_status"
      package static let canonicalANEProbeSource = "terra.hw.ane.probe_source"
      package static let aneSegmentCount = "terra.ane.segment_count"
      package static let aneFullyANE = "terra.ane.fully_ane"
      package static let aneAvailable = "terra.ane.available"

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
