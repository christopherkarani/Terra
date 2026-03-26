import Foundation
import OpenTelemetryApi
import TerraCore
#if canImport(ObjectiveC)
import ObjectiveC.runtime
#endif

final class HTTPAIStreamingObserver: @unchecked Sendable {
    static let shared = HTTPAIStreamingObserver()

    private let lock = NSLock()
    private var states: [String: State] = [:]
    private var installed = false
    private var swizzledKeys: Set<String> = []

    private let streamSpanIDProperty = "io.opentelemetry.terra.http.span_id"
    private let streamEnabledProperty = "io.opentelemetry.terra.http.stream_enabled"

    private struct State {
        let span: any Span
        let startedAt: ContinuousClock.Instant
        var firstChunkAt: ContinuousClock.Instant?
        var chunkCount = 0
        var outputTokens: Int?
    }

    func installIfNeeded() {
        #if canImport(ObjectiveC)
        lock.lock()
        if installed {
            lock.unlock()
            return
        }
        installed = true
        lock.unlock()

        swizzle(selector: #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)))
        swizzle(selector: #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)))
        #endif
    }

    func attachProperties(to request: inout URLRequest, span: (any Span)?, parsedRequest: ParsedRequest?) {
        guard let span, parsedRequest?.stream == true else { return }
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(span.context.spanId.hexString, forKey: streamSpanIDProperty, in: mutableRequest)
        URLProtocol.setProperty(true, forKey: streamEnabledProperty, in: mutableRequest)
        request = mutableRequest as URLRequest
    }

    func register(request: URLRequest, span: any Span, parsedRequest: ParsedRequest?) {
        guard parsedRequest?.stream == true, let spanID = spanID(for: request) else { return }
        lock.lock()
        states[spanID] = State(span: span, startedAt: .now)
        lock.unlock()
    }

    func recordChunk(for request: URLRequest?, data: Data) {
        guard let request, isStreaming(request: request), let spanID = spanID(for: request) else { return }

        let now = ContinuousClock.now
        let timestamp = Date()
        var span: (any Span)?
        var chunkIndex = 0
        var shouldEmitFirstToken = false
        var outputTokens: Int?

        lock.lock()
        if var state = states[spanID] {
            state.chunkCount += 1
            chunkIndex = state.chunkCount
            if state.firstChunkAt == nil {
                state.firstChunkAt = now
                shouldEmitFirstToken = true
            }
            if let parsedOutputTokens = AIStreamingChunkParser.outputTokens(from: data) {
                state.outputTokens = parsedOutputTokens
            }
            outputTokens = state.outputTokens
            span = state.span
            states[spanID] = state
        }
        lock.unlock()

        guard let span else { return }
        if shouldEmitFirstToken {
            span.addEvent(name: Terra.Keys.Terra.streamFirstTokenEvent, timestamp: timestamp)
        }

        var attributes: [String: AttributeValue] = [
            "chunk_index": .int(chunkIndex),
        ]
        if let outputTokens {
            attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(outputTokens)
        }
        span.addEvent(name: "stream.chunk", attributes: attributes, timestamp: timestamp)
    }

    func finish(span: any Span, parsedResponse: ParsedResponse?) {
        let spanID = span.context.spanId.hexString
        let now = ContinuousClock.now
        var state: State?

        lock.lock()
        state = states.removeValue(forKey: spanID)
        lock.unlock()

        guard let state else { return }

        var attributes: [String: AttributeValue] = [
            Terra.Keys.Terra.streamChunkCount: .int(state.chunkCount),
        ]

        let resolvedOutputTokens = parsedResponse?.outputTokens ?? state.outputTokens
        if let resolvedOutputTokens {
            attributes[Terra.Keys.GenAI.usageOutputTokens] = .int(resolvedOutputTokens)
            attributes[Terra.Keys.Terra.streamOutputTokens] = .int(resolvedOutputTokens)
        }
        if let firstChunkAt = state.firstChunkAt {
            let ttft = durationToMs(state.startedAt.duration(to: firstChunkAt))
            attributes[Terra.Keys.Terra.streamTimeToFirstTokenMs] = .double(ttft)
            if let resolvedOutputTokens {
                let generationDuration = firstChunkAt.duration(to: now)
                let generationSeconds = max(durationToSeconds(generationDuration), 0.000_001)
                attributes[Terra.Keys.Terra.streamTokensPerSecond] = .double(Double(resolvedOutputTokens) / generationSeconds)
            }
        }

        span.setAttributes(attributes)
    }

    func finishWithError(request: URLRequest?) {
        guard let request, let spanID = spanID(for: request) else { return }
        lock.lock()
        states.removeValue(forKey: spanID)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        states.removeAll()
        lock.unlock()
    }

    private func spanID(for request: URLRequest) -> String? {
        URLProtocol.property(forKey: streamSpanIDProperty, in: request) as? String
    }

    private func isStreaming(request: URLRequest) -> Bool {
        (URLProtocol.property(forKey: streamEnabledProperty, in: request) as? Bool) == true
    }

    private func durationToMs(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private func durationToSeconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    #if canImport(ObjectiveC)
    private func swizzle(selector: Selector) {
        var classCount: UInt32 = 0
        guard let classList = objc_copyClassList(&classCount) else { return }
        defer { free(UnsafeMutableRawPointer(classList)) }

        for index in 0 ..< Int(classCount) {
            let cls: AnyClass = classList[index]
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            swizzle(method: method, selector: selector)
        }
    }

    private func swizzle(method: Method, selector: Selector) {
        guard let owningClass: AnyClass = method_getClass(method) else { return }
        let key = "\(NSStringFromClass(owningClass))::\(NSStringFromSelector(selector))"
        lock.lock()
        if swizzledKeys.contains(key) {
            lock.unlock()
            return
        }
        swizzledKeys.insert(key)
        lock.unlock()

        var originalIMP: IMP?

        switch selector {
        case #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)):
            let block: @convention(block) (AnyObject, URLSession, URLSessionDataTask, Data) -> Void = { object, session, dataTask, data in
                self.recordChunk(for: dataTask.currentRequest ?? dataTask.originalRequest, data: data)
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, URLSession, URLSessionDataTask, Data) -> Void).self)
                castedIMP(object, selector, session, dataTask, data)
            }
            originalIMP = method_setImplementation(method, imp_implementationWithBlock(block))

        case #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)):
            let block: @convention(block) (AnyObject, URLSession, URLSessionTask, Error?) -> Void = { object, session, task, error in
                if error != nil {
                    self.finishWithError(request: task.currentRequest ?? task.originalRequest)
                }
                let castedIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, URLSession, URLSessionTask, Error?) -> Void).self)
                castedIMP(object, selector, session, task, error)
            }
            originalIMP = method_setImplementation(method, imp_implementationWithBlock(block))

        default:
            return
        }
    }

    private func method_getClass(_ method: Method) -> AnyClass? {
        let selector = method_getName(method)
        var classCount: UInt32 = 0
        guard let classList = objc_copyClassList(&classCount) else { return nil }
        defer { free(UnsafeMutableRawPointer(classList)) }

        for index in 0 ..< Int(classCount) {
            let cls: AnyClass = classList[index]
            if class_getInstanceMethod(cls, selector) == method {
                return cls
            }
        }
        return nil
    }
    #endif
}
