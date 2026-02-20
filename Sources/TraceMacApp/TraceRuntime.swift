import Foundation
import TerraTraceKit
import OpenTelemetryApi

enum TraceRuntimeFilter: String, CaseIterable, Sendable {
    case all
    case coreML
    case foundationModels
    case mlx
    case ollama
    case lmStudio
    case llamaCpp
    case openClawGateway
    case httpAPI
    case other

    var title: String {
        switch self {
        case .all:
            "All"
        case .coreML:
            "CoreML"
        case .foundationModels:
            "Foundation Models"
        case .mlx:
            "MLX"
        case .ollama:
            "Ollama"
        case .lmStudio:
            "LM Studio"
        case .llamaCpp:
            "llama.cpp"
        case .openClawGateway:
            "OpenClaw Gateway"
        case .httpAPI:
            "HTTP API"
        case .other:
            "Other"
        }
    }
}

extension Trace {
    var runtimeAttribute: String? {
        for span in spans {
            if let runtime = openTelemetryValueString(span.attributes["terra.runtime"])?.lowercased(),
               !runtime.isEmpty {
                return runtime
            }
            if openTelemetryValueString(span.attributes["terra.runtime.class"])?.lowercased() == "openclaw_gateway" {
                return "openclaw_gateway"
            }
        }
        return nil
    }

    var detectedRuntime: TraceRuntimeFilter {
        if openClawSource == .gateway || attributesContainOpenClaw {
            return .openClawGateway
        }

        guard let raw = runtimeAttribute else { return .other }
        switch raw {
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
        case "http_api", "http", "httpapi":
            return .httpAPI
        default:
            return .other
        }
    }

    var detectedRuntimeTitle: String {
        detectedRuntime.title
    }

    private var attributesContainOpenClaw: Bool {
        for span in spans {
            if let value = span.attributes["terra.openclaw.gateway"]?.description,
               value.lowercased() == "true" {
                return true
            }
            if let mode = openTelemetryValueString(span.attributes["terra.openclaw.mode"]),
               mode.lowercased().contains("gateway") {
                return true
            }
        }
        return false
    }
}

private func openTelemetryValueString(_ value: OpenTelemetryApi.AttributeValue?) -> String? {
    guard let value else { return nil }
    switch value {
    case .string(let string):
        return string
    case .bool(let bool):
        return bool ? "true" : "false"
    case .int(let int):
        return String(int)
    case .double(let double):
        return String(double)
    default:
        return nil
    }
}
