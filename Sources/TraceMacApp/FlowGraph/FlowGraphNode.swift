import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi

/// The kind of flow graph node, classified from span attributes.
enum FlowNodeKind: Equatable {
    case agent(name: String, id: String?)
    case inference(model: String, inputTokens: Int, outputTokens: Int, isStreaming: Bool)
    case tool(name: String, callID: String?, type: String?)
    case stage(name: String)
    case embedding(model: String, inputCount: Int)
    case safetyCheck(name: String)
    case generic

    var icon: String {
        switch self {
        case .agent: return "person.crop.rectangle"
        case .inference: return "brain"
        case .tool: return "wrench.and.screwdriver"
        case .stage: return "gauge.medium"
        case .embedding: return "square.grid.3x3"
        case .safetyCheck: return "shield.checkered"
        case .generic: return "circle"
        }
    }

    var label: String {
        switch self {
        case .agent(let name, _): return name
        case .inference(let model, _, _, _): return model
        case .tool(let name, _, _): return name
        case .stage(let name): return name
        case .embedding(let model, _): return model
        case .safetyCheck(let name): return name
        case .generic: return "span"
        }
    }

    var isAgent: Bool {
        if case .agent = self { return true }
        return false
    }

    /// Classify a span into a node kind without constructing a FlowGraphNode.
    static func classify(span: SpanData) -> FlowNodeKind {
        let attrs = span.attributes
        let opName = attrs["gen_ai.operation.name"]?.description ?? ""
        let modelName = attrs["gen_ai.request.model"]?.description
            ?? attrs["gen_ai.response.model"]?.description
        let agentN = attrs["gen_ai.agent.name"]?.description
        let toolN = attrs["gen_ai.tool.name"]?.description
        let toolType = attrs["gen_ai.tool.type"]?.description
        let toolCallId = attrs["gen_ai.tool.call.id"]?.description
        let agentId = attrs["gen_ai.agent.id"]?.description
        let inputTok = FlowGraphNode.intAttribute(attrs["gen_ai.usage.input_tokens"])
        let outputTok = FlowGraphNode.intAttribute(attrs["gen_ai.usage.output_tokens"])
        let isStreaming = attrs["gen_ai.request.stream"]?.description == "true"
        let stageName = attrs["terra.stage.name"]?.description
        let safetyName = attrs["terra.safety.check.name"]?.description
        let embeddingCount = FlowGraphNode.intAttribute(attrs["terra.embeddings.input.count"])

        switch opName {
        case "invoke_agent":
            return .agent(name: agentN ?? span.name, id: agentId)
        case "inference", "chat", "text_completion":
            return .inference(model: modelName ?? "unknown", inputTokens: inputTok, outputTokens: outputTok, isStreaming: isStreaming)
        case "execute_tool":
            return .tool(name: toolN ?? span.name, callID: toolCallId, type: toolType)
        case "prompt_eval", "decode", "stream_lifecycle":
            return .stage(name: stageName ?? opName)
        case "safety_check":
            return .safetyCheck(name: safetyName ?? span.name)
        case "embeddings":
            return .embedding(model: modelName ?? "unknown", inputCount: embeddingCount)
        default:
            switch span.name {
            case "terra.agent":
                return .agent(name: agentN ?? "agent", id: agentId)
            case "terra.inference":
                return .inference(model: modelName ?? "unknown", inputTokens: inputTok, outputTokens: outputTok, isStreaming: isStreaming)
            case "terra.tool":
                return .tool(name: toolN ?? "tool", callID: toolCallId, type: toolType)
            case "terra.stage.prompt_eval":
                return .stage(name: "prompt_eval")
            case "terra.stage.decode":
                return .stage(name: "decode")
            case "terra.stream.lifecycle":
                return .stage(name: "stream_lifecycle")
            case "terra.safety_check":
                return .safetyCheck(name: safetyName ?? "safety_check")
            case "terra.embeddings":
                return .embedding(model: modelName ?? "unknown", inputCount: embeddingCount)
            default:
                return .generic
            }
        }
    }
}

/// Status of a flow graph node.
enum FlowNodeStatus: Equatable {
    case pending
    case running
    case completed
    case error
}

/// Progressive reveal phase for flow graph nodes during live streaming.
enum RevealPhase: Int, Comparable {
    case started = 0    // name + running status pulse only
    case metrics = 1    // duration + TTFT appear
    case streaming = 2  // token count updates live, TPS appears
    case complete = 3   // all metrics shown, final status

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A single node in the flow graph, representing one span.
final class FlowGraphNode: Identifiable, ObservableObject {
    let id: String
    let spanId: String
    let parentSpanId: String?
    let spanName: String
    let kind: FlowNodeKind
    @Published var status: FlowNodeStatus
    @Published var revealPhase: RevealPhase
    @Published var liveOutputTokens: Int = 0
    @Published var liveTPS: Double? = nil
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval

    // Extracted telemetry
    let model: String?
    let agentName: String?
    let toolName: String?
    let inputTokens: Int
    let outputTokens: Int
    let tokensPerSecond: Double?
    let ttftMs: Double?

    // Content previews
    let promptPreview: String?
    let completionPreview: String?

    // Mutable layout state
    var position: CGPoint = .zero
    var size: CGSize = .zero
    var childIDs: [String] = []
    var depth: Int = 0

    init(span: SpanData) {
        self.id = span.spanId.hexString
        self.spanId = span.spanId.hexString
        self.parentSpanId = span.parentSpanId?.hexString
        self.spanName = span.name
        self.startTime = span.startTime
        self.endTime = span.endTime
        self.duration = span.endTime.timeIntervalSince(span.startTime)

        // Extract attributes (inline key strings to avoid Terra module dependency)
        let attrs = span.attributes
        let opName = attrs["gen_ai.operation.name"]?.description ?? ""
        let modelName = attrs["gen_ai.request.model"]?.description
            ?? attrs["gen_ai.response.model"]?.description
        let agentN = attrs["gen_ai.agent.name"]?.description
        let toolN = attrs["gen_ai.tool.name"]?.description
        let toolType = attrs["gen_ai.tool.type"]?.description
        let toolCallId = attrs["gen_ai.tool.call.id"]?.description
        let agentId = attrs["gen_ai.agent.id"]?.description
        let inputTok = Self.intAttribute(attrs["gen_ai.usage.input_tokens"])
        let outputTok = Self.intAttribute(attrs["gen_ai.usage.output_tokens"])
        let tps = Self.doubleAttribute(attrs["terra.stream.tokens_per_second"])
        let ttft = Self.doubleAttribute(attrs["terra.latency.ttft_ms"])
        let isStreaming = attrs["gen_ai.request.stream"]?.description == "true"
        let stageName = attrs["terra.stage.name"]?.description
        let safetyName = attrs["terra.safety.check.name"]?.description
        let embeddingCount = Self.intAttribute(attrs["terra.embeddings.input.count"])

        self.model = modelName
        self.agentName = agentN
        self.toolName = toolN
        self.inputTokens = inputTok
        self.outputTokens = outputTok
        self.tokensPerSecond = tps
        self.ttftMs = ttft

        // Classify node kind using operationName first, then span name fallback
        switch opName {
        case "invoke_agent":
            self.kind = .agent(name: agentN ?? span.name, id: agentId)
        case "inference", "chat", "text_completion":
            self.kind = .inference(model: modelName ?? "unknown", inputTokens: inputTok, outputTokens: outputTok, isStreaming: isStreaming)
        case "execute_tool":
            self.kind = .tool(name: toolN ?? span.name, callID: toolCallId, type: toolType)
        case "prompt_eval", "decode", "stream_lifecycle":
            self.kind = .stage(name: stageName ?? opName)
        case "safety_check":
            self.kind = .safetyCheck(name: safetyName ?? span.name)
        case "embeddings":
            self.kind = .embedding(model: modelName ?? "unknown", inputCount: embeddingCount)
        default:
            // Fallback classification by Terra span name constants
            switch span.name {
            case "terra.agent":
                self.kind = .agent(name: agentN ?? "agent", id: agentId)
            case "terra.inference":
                self.kind = .inference(model: modelName ?? "unknown", inputTokens: inputTok, outputTokens: outputTok, isStreaming: isStreaming)
            case "terra.tool":
                self.kind = .tool(name: toolN ?? "tool", callID: toolCallId, type: toolType)
            case "terra.stage.prompt_eval":
                self.kind = .stage(name: "prompt_eval")
            case "terra.stage.decode":
                self.kind = .stage(name: "decode")
            case "terra.stream.lifecycle":
                self.kind = .stage(name: "stream_lifecycle")
            case "terra.safety_check":
                self.kind = .safetyCheck(name: safetyName ?? "safety_check")
            case "terra.embeddings":
                self.kind = .embedding(model: modelName ?? "unknown", inputCount: embeddingCount)
            default:
                self.kind = .generic
            }
        }

        // Content previews (first 120 chars)
        let rawPrompt = attrs["terra.content.prompt"]?.description
        let rawCompletion = attrs["terra.content.completion"]?.description
        self.promptPreview = rawPrompt.map { String($0.prefix(120)) }
        self.completionPreview = rawCompletion.map { String($0.prefix(120)) }

        // Determine status
        if span.status.isError {
            self.status = .error
        } else if span.endTime <= span.startTime {
            self.status = .running
        } else {
            self.status = .completed
        }

        // Determine reveal phase
        if span.endTime > span.startTime {
            self.revealPhase = .complete
        } else if outputTok > 0 {
            self.revealPhase = .streaming
        } else if span.endTime <= span.startTime && outputTok == 0 {
            self.revealPhase = .started
        } else {
            self.revealPhase = .metrics
        }
    }

    var stageTokenCount: Int? {
        let val = inputTokens + outputTokens
        return val > 0 ? val : nil
    }

    static func intAttribute(_ value: AttributeValue?) -> Int {
        guard let value else { return 0 }
        switch value {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let s): return Int(s) ?? 0
        default: return 0
        }
    }

    static func doubleAttribute(_ value: AttributeValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}
