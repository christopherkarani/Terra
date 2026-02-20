import Foundation
import TerraTraceKit

enum OpenClawTraceSource: String, Sendable {
    case gateway
    case diagnostics
    case other

    var title: String {
        switch self {
        case .gateway:
            return "Gateway"
        case .diagnostics:
            return "Diagnostics"
        case .other:
            return "Other"
        }
    }
}

enum OpenClawTraceSourceFilter: String, CaseIterable, Sendable {
    case all
    case gateway
    case diagnostics

    var title: String {
        switch self {
        case .all:
            return "All"
        case .gateway:
            return "Gateway"
        case .diagnostics:
            return "Diagnostics"
        }
    }
}

extension Trace {
    var openClawSource: OpenClawTraceSource {
        let loweredID = id.lowercased()
        if loweredID.contains("diagnostics")
            || loweredID.contains("gateway.log")
            || loweredID.contains("openclaw-")
        {
            return .diagnostics
        }

        for span in spans {
            if let gatewayValue = span.attributes["terra.openclaw.gateway"],
               gatewayValue.description.lowercased() == "true"
            {
                return .gateway
            }

            if let runtime = span.attributes["terra.runtime"]?.description.lowercased(),
               runtime == "openclaw_gateway"
            {
                return .gateway
            }

            if let mode = span.attributes["terra.openclaw.mode"]?.description.lowercased(),
               mode.contains("diagnostics")
            {
                return .diagnostics
            }
        }

        return .other
    }
}
