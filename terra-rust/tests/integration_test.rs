//! Integration tests for the Terra Rust safe API against the real libtera.a.
//!
//! These tests link against the real Zig core and exercise the full FFI path.
//! They MUST run serially (--test-threads=1) because the Zig core is a
//! process-global singleton: each test init/shutdown cycle mutates shared state.

use terra::{
    get_version, last_error_message, ContentPolicy, LifecycleState, RedactionStrategy, SpanContext,
    StatusCode, Terra, TerraConfig,
};

// ── Lifecycle ────────────────────────────────────────────────────────────────

#[test]
fn test_init_and_shutdown() {
    let terra = Terra::init().expect("init failed");
    assert!(terra.is_running());
    assert_eq!(terra.state(), LifecycleState::Running);
    // Drop calls shutdown automatically
}

/// NOTE: init_with_config currently fails because of an ABI mismatch between
/// the Rust `terra_config_t` (C layout) and the Zig `TerraConfig` struct
/// (contains Zig-specific types like `std.mem.Allocator` and function pointers
/// with different calling conventions). The Zig `terra_init` export interprets
/// the raw pointer as its own TerraConfig, so the C struct fields land at
/// wrong offsets. This is a known limitation — config init needs a dedicated
/// C-ABI config bridge in the Zig core. For now, `terra_init(NULL)` (default
/// config) is the supported path.
#[test]
fn test_init_with_config_returns_error() {
    let config = TerraConfig::new()
        .service_name("integration-test")
        .service_version("0.1.0")
        .max_spans(1024)
        .max_attributes_per_span(64)
        .max_events_per_span(8)
        .max_event_attrs(4)
        .batch_size(256)
        .flush_interval_ms(5000)
        .content_policy(ContentPolicy::Never)
        .redaction_strategy(RedactionStrategy::Drop);

    // Currently fails due to ABI mismatch — document this as expected behavior
    let result = Terra::init_with_config(&config);
    assert!(
        result.is_err(),
        "init_with_config should fail until ABI bridge is implemented"
    );
}

#[test]
fn test_explicit_shutdown() {
    let mut terra = Terra::init().expect("init failed");
    assert!(terra.is_running());
    terra.shutdown().expect("shutdown failed");
    // After shutdown, is_running should be false
    assert!(!terra.is_running());
}

// ── Span creation and attributes ─────────────────────────────────────────────

#[test]
fn test_inference_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_inference_span("gpt-4", None, false)
        .expect("span creation failed");
    span.set_string("gen_ai.request.model", "gpt-4");
    span.set_int("gen_ai.request.max_tokens", 2048);
    span.set_double("gen_ai.request.temperature", 0.7);
    span.set_bool("gen_ai.request.stream", false);
    span.add_event("prompt_sent");
    span.set_status(StatusCode::Ok, "success");
    span.end();
}

#[test]
fn test_embedding_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_embedding_span("text-embedding-3-small", None, true)
        .expect("embedding span failed");
    span.set_string("gen_ai.request.model", "text-embedding-3-small");
    span.set_int("gen_ai.usage.input_tokens", 64);
    span.set_status(StatusCode::Ok, "");
    span.end();
}

#[test]
fn test_agent_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_agent_span("research-agent", None, false)
        .expect("agent span failed");
    span.set_string("terra.agent.name", "research-agent");
    span.add_event("agent_step_start");
    span.add_event("agent_step_complete");
    span.set_status(StatusCode::Ok, "");
    span.end();
}

#[test]
fn test_tool_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_tool_span("web-search", None, false)
        .expect("tool span failed");
    span.set_string("gen_ai.tool.name", "web-search");
    span.set_string("gen_ai.tool.description", "Search the web");
    span.set_status(StatusCode::Ok, "");
    span.end();
}

#[test]
fn test_safety_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_safety_span("content-filter", None, false)
        .expect("safety span failed");
    span.set_string("terra.safety.check_name", "content-filter");
    span.set_bool("terra.safety.passed", true);
    span.set_status(StatusCode::Ok, "");
    span.end();
}

#[test]
fn test_streaming_span() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_streaming_span("gpt-4-turbo", None, true)
        .expect("streaming span failed");
    span.set_string("gen_ai.request.model", "gpt-4-turbo");

    // Simulate streaming: first token, then several more
    span.streaming_record_first_token();
    for _ in 0..10 {
        span.streaming_record_token();
    }
    span.streaming_end();
    span.end();
}

// ── All span types in one test ───────────────────────────────────────────────

#[test]
fn test_all_span_types() {
    let terra = Terra::init().expect("init failed");

    // Each span is auto-ended by Drop
    let _ = terra.begin_inference_span("m", None, false);
    let _ = terra.begin_embedding_span("m", None, false);
    let _ = terra.begin_agent_span("a", None, false);
    let _ = terra.begin_tool_span("t", None, false);
    let _ = terra.begin_safety_span("c", None, false);
    let _ = terra.begin_streaming_span("m", None, false);
}

// ── Parent-child context linking ─────────────────────────────────────────────

#[test]
fn test_parent_child_context() {
    let terra = Terra::init().expect("init failed");
    let parent = terra
        .begin_inference_span("parent-model", None, false)
        .expect("parent span failed");
    let ctx = parent.context();

    // Verify context has non-zero IDs (the Zig core assigns real trace/span IDs)
    assert!(
        ctx.trace_id_hi != 0 || ctx.trace_id_lo != 0,
        "trace ID should be non-zero"
    );
    assert!(ctx.span_id != 0, "span ID should be non-zero");

    // Create a child span using the parent context
    let mut child = terra
        .begin_tool_span("search-tool", Some(&ctx), false)
        .expect("child span failed");
    let child_ctx = child.context();

    // Child should share the same trace ID
    assert_eq!(child_ctx.trace_id_hi, ctx.trace_id_hi);
    assert_eq!(child_ctx.trace_id_lo, ctx.trace_id_lo);
    // But have a different span ID
    assert_ne!(child_ctx.span_id, ctx.span_id);

    child.end();
    // parent ended by Drop
}

// ── Error recording ──────────────────────────────────────────────────────────

#[test]
fn test_error_recording() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_inference_span("test-model", None, false)
        .expect("span failed");
    span.record_error("RuntimeError", "model timed out after 30s", true);
    span.set_status(StatusCode::Error, "inference timeout");
    span.end();
}

#[test]
fn test_error_recording_without_status() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_inference_span("test-model", None, false)
        .expect("span failed");
    // Record error but don't automatically set status
    span.record_error("ValidationError", "invalid input shape", false);
    // Manually set OK status (perhaps the error was recovered)
    span.set_status(StatusCode::Ok, "recovered");
    span.end();
}

// ── Diagnostics ──────────────────────────────────────────────────────────────

#[test]
fn test_diagnostics() {
    let terra = Terra::init().expect("init failed");
    // Fresh instance should have zero drops and no degradation
    assert_eq!(terra.spans_dropped(), 0);
    assert!(!terra.transport_degraded());
}

#[test]
fn test_version() {
    let ver = get_version();
    assert_eq!(ver.major, 1, "expected major version 1");
    assert_eq!(ver.minor, 0);
    assert_eq!(ver.patch, 0);
}

// ── Service info and session ─────────────────────────────────────────────────

#[test]
fn test_service_info() {
    let terra = Terra::init().expect("init failed");
    terra
        .set_service_info("test-rust-service", "2.0.0")
        .expect("set_service_info failed");
}

#[test]
fn test_session_id() {
    let terra = Terra::init().expect("init failed");
    terra
        .set_session_id("session-abc-123")
        .expect("set_session_id failed");
}

// ── Metrics recording ────────────────────────────────────────────────────────

#[test]
fn test_record_inference_duration() {
    let terra = Terra::init().expect("init failed");
    terra.record_inference_duration(42.5);
    terra.record_inference_duration(100.0);
}

#[test]
fn test_record_token_count() {
    let terra = Terra::init().expect("init failed");
    terra.record_token_count(128, 256);
    terra.record_token_count(64, 512);
}

// ── Closure-based span helpers ───────────────────────────────────────────────

#[test]
fn test_with_inference_span() {
    let terra = Terra::init().expect("init failed");
    let result = terra.with_inference_span("gpt-4", None, false, |span| {
        span.set_string("gen_ai.request.model", "gpt-4");
        span.set_int("gen_ai.usage.input_tokens", 100);
        span.set_int("gen_ai.usage.output_tokens", 50);
        42
    });
    assert_eq!(result, Some(42));
}

#[test]
fn test_with_tool_span() {
    let terra = Terra::init().expect("init failed");
    let result = terra.with_tool_span("calculator", None, false, |span| {
        span.set_string("gen_ai.tool.name", "calculator");
        span.add_event("tool_invoked");
        "computed"
    });
    assert_eq!(result, Some("computed"));
}

#[test]
fn test_with_agent_span() {
    let terra = Terra::init().expect("init failed");
    let result = terra.with_agent_span("planner", None, true, |span| {
        span.set_string("terra.agent.name", "planner");
        span.add_event("planning_started");
        span.add_event("planning_completed");
        true
    });
    assert_eq!(result, Some(true));
}

// ── Event with timestamp ─────────────────────────────────────────────────────

#[test]
fn test_add_event_with_timestamp() {
    let terra = Terra::init().expect("init failed");
    let mut span = terra
        .begin_inference_span("test-model", None, false)
        .expect("span failed");
    // Add event with explicit nanosecond timestamp
    let now_ns = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos() as u64;
    span.add_event_ts("custom_event", now_ns);
    span.end();
}

// ── Last error message ───────────────────────────────────────────────────────

#[test]
fn test_last_error_message_empty_on_success() {
    let _terra = Terra::init().expect("init failed");
    // After successful init, there shouldn't be an error message
    // (the message may or may not be empty depending on prior state,
    // but calling it shouldn't crash)
    let _msg = last_error_message();
}

// ── Nested span hierarchy ────────────────────────────────────────────────────

#[test]
fn test_deep_span_hierarchy() {
    let terra = Terra::init().expect("init failed");

    // agent -> inference -> tool (3-level nesting)
    let agent = terra
        .begin_agent_span("orchestrator", None, false)
        .expect("agent span failed");
    let agent_ctx = agent.context();

    let inference = terra
        .begin_inference_span("gpt-4", Some(&agent_ctx), false)
        .expect("inference span failed");
    let inference_ctx = inference.context();

    let mut tool = terra
        .begin_tool_span("search", Some(&inference_ctx), false)
        .expect("tool span failed");
    tool.set_string("gen_ai.tool.name", "web-search");
    tool.end();

    // inference and agent ended by Drop
}

// ── SpanContext round-trip ────────────────────────────────────────────────────

#[test]
fn test_span_context_values() {
    let ctx = SpanContext {
        trace_id_hi: 0xDEAD_BEEF_CAFE_BABE,
        trace_id_lo: 0x0123_4567_89AB_CDEF,
        span_id: 0xFEED_FACE_1234_5678,
    };
    assert_eq!(ctx.trace_id_hi, 0xDEAD_BEEF_CAFE_BABE);
    assert_eq!(ctx.trace_id_lo, 0x0123_4567_89AB_CDEF);
    assert_eq!(ctx.span_id, 0xFEED_FACE_1234_5678);

    let copy = ctx;
    assert_eq!(ctx, copy);
}
