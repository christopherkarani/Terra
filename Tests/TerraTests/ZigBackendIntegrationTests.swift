#if canImport(CTerraBridge)

import Testing
import CTerraBridge

@Suite("Zig Backend Integration", .serialized)
struct ZigBackendIntegrationTests {

    @Test func terraInitAndShutdown() {
        let inst = terra_init(nil)
        #expect(inst != nil, "terra_init returned nil")
        #expect(terra_is_running(inst))

        let ver = terra_get_version()
        #expect(ver.major == 1)
        #expect(ver.minor == 0)

        let result = terra_shutdown(inst)
        #expect(result == 0, "terra_shutdown failed with \(result)")
    }

    @Test func inferenceSpanLifecycle() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        let span = terra_begin_inference_span_ctx(inst, nil, "gpt-4", false)
        #expect(span != nil, "inference span creation failed")

        terra_span_set_string(span, "gen_ai.request.model", "gpt-4")
        terra_span_set_int(span, "gen_ai.request.max_tokens", 2048)
        terra_span_set_double(span, "gen_ai.request.temperature", 0.7)
        terra_span_set_bool(span, "gen_ai.request.stream", false)
        terra_span_add_event(span, "prompt_sent")

        terra_span_end(inst, span)
    }

    @Test func allSixSpanTypes() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        let spans: [OpaquePointer?] = [
            terra_begin_inference_span_ctx(inst, nil, "m", false),
            terra_begin_embedding_span_ctx(inst, nil, "m", false),
            terra_begin_agent_span_ctx(inst, nil, "a", false),
            terra_begin_tool_span_ctx(inst, nil, "t", false),
            terra_begin_safety_span_ctx(inst, nil, "c", false),
            terra_begin_streaming_span_ctx(inst, nil, "m", false),
        ]

        for span in spans {
            #expect(span != nil)
            terra_span_end(inst, span)
        }
    }

    @Test func parentChildContextPropagation() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        let parent = terra_begin_inference_span_ctx(inst, nil, "parent", false)!
        let ctx = terra_span_context(parent)

        #expect(ctx.trace_id_hi != 0 || ctx.trace_id_lo != 0, "trace_id is zero")
        #expect(ctx.span_id != 0, "span_id is zero")

        // Create child with parent context
        var parentCtx = ctx
        let child = withUnsafePointer(to: &parentCtx) { ptr in
            terra_begin_tool_span_ctx(inst, ptr, "child-tool", false)
        }
        #expect(child != nil)

        // Child should share the same trace ID
        let childCtx = terra_span_context(child!)
        #expect(childCtx.trace_id_hi == ctx.trace_id_hi, "child trace_id_hi mismatch")
        #expect(childCtx.trace_id_lo == ctx.trace_id_lo, "child trace_id_lo mismatch")
        #expect(childCtx.span_id != ctx.span_id, "child span_id should differ from parent")

        terra_span_end(inst, child)
        terra_span_end(inst, parent)
    }

    @Test func errorRecording() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        let span = terra_begin_inference_span_ctx(inst, nil, "test", false)!
        terra_span_record_error(span, "RuntimeError", "test error", true)
        terra_span_set_status(span, UInt8(TERRA_STATUS_ERROR.rawValue), "error occurred")
        terra_span_end(inst, span)
    }

    @Test func sessionAndServiceInfo() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        #expect(terra_set_session_id(inst, "swift-session-42") == 0)
        #expect(terra_set_service_info(inst, "swift-test", "1.0.0") == 0)
    }

    @Test func diagnostics() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        #expect(terra_spans_dropped(inst) == 0)
        // transport_degraded may be true or false depending on state
        _ = terra_transport_degraded(inst)
    }

    @Test func drainAndReset() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        // Create and end a span
        let span = terra_begin_inference_span_ctx(inst, nil, "drain-test", false)!
        terra_span_end(inst, span)

        // Reset clears all state
        terra_test_reset(inst)
    }

    @Test func nullSafety() {
        // All these should be no-ops, not crashes
        terra_span_set_string(nil, nil, nil)
        terra_span_set_int(nil, nil, 0)
        terra_span_set_double(nil, nil, 0.0)
        terra_span_set_bool(nil, nil, false)
        terra_span_end(nil, nil)
        terra_span_add_event(nil, nil)
        terra_span_record_error(nil, nil, nil, false)
        _ = terra_spans_dropped(nil)
        _ = terra_transport_degraded(nil)
    }

    @Test func metricsRecording() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        terra_record_inference_duration(inst, 42.5)
        terra_record_token_count(inst, 100, 200)
    }

    @Test func versionIsABIStable() {
        let ver = terra_get_version()
        #expect(ver.major == TERRA_ABI_VERSION_MAJOR)
        #expect(ver.minor == TERRA_ABI_VERSION_MINOR)
        #expect(ver.patch == TERRA_ABI_VERSION_PATCH)
    }

    @Test func multipleInstancesAreIndependent() {
        let inst1 = terra_init(nil)!
        let inst2 = terra_init(nil)!

        // Both should be running
        #expect(terra_is_running(inst1))
        #expect(terra_is_running(inst2))

        // Create span on each
        let span1 = terra_begin_inference_span_ctx(inst1, nil, "inst1", false)!
        let span2 = terra_begin_inference_span_ctx(inst2, nil, "inst2", false)!

        // Spans should have different trace IDs
        let ctx1 = terra_span_context(span1)
        let ctx2 = terra_span_context(span2)
        let sameTrace = ctx1.trace_id_hi == ctx2.trace_id_hi && ctx1.trace_id_lo == ctx2.trace_id_lo
        #expect(!sameTrace, "independent instances should produce different trace IDs")

        terra_span_end(inst1, span1)
        terra_span_end(inst2, span2)

        _ = terra_shutdown(inst1)
        _ = terra_shutdown(inst2)
    }

    @Test func streamingSpanTokenTracking() {
        let inst = terra_init(nil)!
        defer { _ = terra_shutdown(inst) }

        let span = terra_begin_streaming_span_ctx(inst, nil, "stream-model", false)!

        // Record first token and subsequent tokens
        terra_streaming_record_first_token(span)
        for _ in 0..<10 {
            terra_streaming_record_token(span)
        }
        terra_streaming_end(span)

        terra_span_end(inst, span)
    }

    @Test func runtimeConfigurationAfterDefaultInit() {
        // terra_init(nil) uses sensible defaults; runtime APIs customize post-init
        let inst = terra_init(nil)!

        #expect(terra_set_service_info(inst, "configured-svc", "1.2.3") == 0)
        #expect(terra_set_session_id(inst, "config-session") == 0)
        #expect(terra_is_running(inst))

        // Create a span to confirm the instance is fully operational
        let span = terra_begin_inference_span_ctx(inst, nil, "configured-model", true)
        #expect(span != nil)
        terra_span_set_string(span, "gen_ai.request.model", "configured-model")
        terra_span_end(inst, span)

        _ = terra_shutdown(inst)
    }

    @Test func configWithInvalidParamsReturnsNil() {
        // A zeroed config (no vtables, no endpoint) is rejected as invalid
        var config = terra_config_t()
        config.max_spans = 128
        let inst = terra_init(&config)
        #expect(inst == nil, "terra_init should reject incomplete config")
        #expect(terra_last_error() == Int32(TERRA_ERR_INVALID_CONFIG.rawValue))
    }

    @Test func lastErrorAccessible() {
        // terra_last_error should return 0 (no error) at start
        let err = terra_last_error()
        // The initial value is implementation-dependent but should not crash
        _ = err

        // terra_last_error_message should handle a buffer
        var buf = [CChar](repeating: 0, count: 256)
        let written = terra_last_error_message(&buf, 256)
        // written is 0 if no error, or the message length
        _ = written
    }
}

#else
// When CTerraBridge is not available, include a placeholder test
import Testing

@Suite("Zig Backend Integration (Unavailable)")
struct ZigBackendUnavailableTests {
    @Test func zigBackendNotAvailable() {
        // CTerraBridge not importable — Zig backend tests skipped
        #expect(true, "Zig backend not available on this platform")
    }
}
#endif
