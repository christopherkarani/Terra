//! Basic usage example for the Terra Rust bindings.
//!
//! Run with: cargo run --example basic
//! (Requires libtera to be built: cd ../zig-core && zig build)

use terra::{ContentPolicy, RedactionStrategy, StatusCode, Terra, TerraConfig};

fn main() {
    // Print library version
    let version = terra::get_version();
    println!(
        "Terra v{}.{}.{}",
        version.major, version.minor, version.patch
    );

    // Build configuration
    let config = TerraConfig::new()
        .service_name("rust-example")
        .service_version("1.0.0")
        .otlp_endpoint("http://localhost:4318")
        .max_spans(4096)
        .content_policy(ContentPolicy::OptIn)
        .redaction_strategy(RedactionStrategy::HmacSha256)
        .hmac_key("my-anonymization-key");

    // Initialize Terra
    let terra = match Terra::init_with_config(&config) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("Failed to initialize Terra: {}", e);
            std::process::exit(1);
        }
    };

    println!("Terra state: {}", terra.state());
    println!("Is running: {}", terra.is_running());

    // Set session ID
    if let Err(e) = terra.set_session_id("session-abc-123") {
        eprintln!("Failed to set session ID: {}", e);
    }

    // ── Inference span (closure-based) ──────────────────────────────────

    terra.with_inference_span("gpt-4o", None, true, |span| {
        span.set_string("gen_ai.request.model", "gpt-4o");
        span.set_int("gen_ai.request.max_tokens", 1024);
        span.set_double("gen_ai.request.temperature", 0.7);

        // Simulate response
        span.set_int("gen_ai.usage.input_tokens", 150);
        span.set_int("gen_ai.usage.output_tokens", 87);
        span.set_status(StatusCode::Ok, "");
        span.add_event("response_received");
    });

    // ── Manual span with parent-child linking ───────────────────────────

    let mut agent_span = terra
        .begin_agent_span("research-agent", None, true)
        .expect("failed to create agent span");

    let agent_ctx = agent_span.context();

    // Child tool span
    if let Some(mut tool_span) =
        terra.begin_tool_span("web_search", Some(&agent_ctx), true)
    {
        tool_span.set_string("terra.tool.name", "web_search");
        tool_span.set_string("terra.tool.input", "latest Rust async patterns");
        tool_span.set_status(StatusCode::Ok, "");
        tool_span.end();
    }

    // Child inference span
    if let Some(mut inference) =
        terra.begin_inference_span("claude-sonnet-4-6-20250514", Some(&agent_ctx), true)
    {
        inference.set_int("gen_ai.usage.input_tokens", 2048);
        inference.set_int("gen_ai.usage.output_tokens", 512);
        inference.set_status(StatusCode::Ok, "");
        inference.end();
    }

    agent_span.set_status(StatusCode::Ok, "agent completed");
    agent_span.end();

    // ── Streaming span ──────────────────────────────────────────────────

    if let Some(mut stream) = terra.begin_streaming_span("gpt-4o", None, true) {
        stream.streaming_record_first_token();
        for _ in 0..50 {
            stream.streaming_record_token();
        }
        stream.streaming_end();
        stream.set_status(StatusCode::Ok, "");
        stream.end();
    }

    // ── Error recording ─────────────────────────────────────────────────

    if let Some(mut span) = terra.begin_inference_span("failing-model", None, false) {
        span.record_error("TimeoutError", "model inference timed out after 30s", true);
        span.end();
    }

    // ── Embedding span ──────────────────────────────────────────────────

    terra.with_embedding_span("text-embedding-3-small", None, false, |span| {
        span.set_int("gen_ai.usage.input_tokens", 64);
        span.set_status(StatusCode::Ok, "");
    });

    // ── Safety check span ───────────────────────────────────────────────

    terra.with_safety_span("content_filter", None, true, |span| {
        span.set_string("terra.safety.result", "pass");
        span.set_bool("terra.safety.flagged", false);
        span.set_status(StatusCode::Ok, "");
    });

    // ── Metrics ─────────────────────────────────────────────────────────

    terra.record_inference_duration(1250.5);
    terra.record_token_count(150, 87);

    // ── Diagnostics ─────────────────────────────────────────────────────

    println!("Spans dropped: {}", terra.spans_dropped());
    println!("Transport degraded: {}", terra.transport_degraded());

    // Terra is shut down automatically when `terra` is dropped.
    println!("Done. Terra will shut down on drop.");
}
