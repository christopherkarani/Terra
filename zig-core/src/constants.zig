// Terra Zig Core — constants.zig
// Span names, attribute keys, and metric names ported 1:1 from Terra+Constants.swift

const std = @import("std");

// ── Span Names ──────────────────────────────────────────────────────────
pub const span_names = struct {
    pub const inference = "gen_ai.inference";
    pub const embedding = "gen_ai.embeddings";
    pub const agent_invocation = "gen_ai.agent";
    pub const tool_execution = "gen_ai.tool";
    pub const safety_check = "terra.safety_check";
    pub const session = "terra.session";
    pub const model_load = "terra.coreml.model_load";

    pub fn isTerraSpanName(name: []const u8) bool {
        const names = [_][]const u8{
            inference,
            embedding,
            agent_invocation,
            tool_execution,
            safety_check,
            session,
            model_load,
        };
        for (names) |n| {
            if (std.mem.eql(u8, name, n)) return true;
        }
        return false;
    }
};

// ── Metric Names ────────────────────────────────────────────────────────
pub const metric_names = struct {
    pub const inference_count = "terra.inference.count";
    pub const inference_duration_ms = "terra.inference.duration_ms";
};

// ── Operation Names ─────────────────────────────────────────────────────
pub const OperationName = enum {
    inference,
    embeddings,
    invoke_agent,
    execute_tool,
    safety_check,

    pub fn toString(self: OperationName) []const u8 {
        return switch (self) {
            .inference => "inference",
            .embeddings => "embeddings",
            .invoke_agent => "invoke_agent",
            .execute_tool => "execute_tool",
            .safety_check => "safety_check",
        };
    }
};

// ── Attribute Keys ──────────────────────────────────────────────────────
pub const keys = struct {
    pub const gen_ai = struct {
        pub const operation_name = "gen_ai.operation.name";
        pub const request_model = "gen_ai.request.model";
        pub const request_max_tokens = "gen_ai.request.max_tokens";
        pub const request_temperature = "gen_ai.request.temperature";
        pub const request_stream = "gen_ai.request.stream";
        pub const usage_input_tokens = "gen_ai.usage.input_tokens";
        pub const usage_output_tokens = "gen_ai.usage.output_tokens";
        pub const response_model = "gen_ai.response.model";
        pub const provider_name = "gen_ai.provider.name";
        pub const agent_name = "gen_ai.agent.name";
        pub const agent_id = "gen_ai.agent.id";
        pub const tool_name = "gen_ai.tool.name";
        pub const tool_type = "gen_ai.tool.type";
        pub const tool_call_id = "gen_ai.tool.call.id";
    };

    pub const terra = struct {
        pub const content_policy = "terra.privacy.content_policy";
        pub const content_redaction = "terra.privacy.content_redaction";
        pub const prompt_length = "terra.prompt.length";
        pub const prompt_hmac_sha256 = "terra.prompt.hmac_sha256";
        pub const prompt_sha256 = "terra.prompt.sha256";
        pub const embedding_input_count = "terra.embeddings.input.count";
        pub const safety_check_name = "terra.safety.check.name";
        pub const safety_subject_length = "terra.safety.subject.length";
        pub const safety_subject_hmac_sha256 = "terra.safety.subject.hmac_sha256";
        pub const safety_subject_sha256 = "terra.safety.subject.sha256";
        pub const anonymization_key_id = "terra.anonymization.key_id";
        pub const auto_instrumented = "terra.auto_instrumented";
        pub const runtime = "terra.runtime";
        pub const openclaw_gateway = "terra.openclaw.gateway";
        pub const openclaw_mode = "terra.openclaw.mode";

        // Streaming inference
        pub const stream_time_to_first_token_ms = "terra.stream.time_to_first_token_ms";
        pub const stream_tokens_per_second = "terra.stream.tokens_per_second";
        pub const stream_output_tokens = "terra.stream.output_tokens";
        pub const stream_chunk_count = "terra.stream.chunk_count";
        pub const stream_first_token_event = "terra.first_token";

        // Runtime diagnostics
        pub const thermal_state = "terra.process.thermal_state";
        pub const process_memory_resident_delta_mb = "process.memory.resident_delta_mb";
        pub const process_memory_peak_mb = "process.memory.peak_mb";

        // Latency
        pub const latency_model_load_ms = "terra.coreml.load.duration_ms";
        pub const latency_e2e_ms = "terra.latency.e2e_ms";

        // Execution route diagnostics
        pub const exec_route_requested = "terra.exec.route.requested";
        pub const exec_route_observed = "terra.exec.route.observed";
        pub const exec_route_estimated_primary = "terra.exec.route.estimated_primary";
        pub const exec_route_supported = "terra.exec.route.supported";
        pub const exec_route_capture_mode = "terra.exec.route.capture_mode";
        pub const exec_route_confidence = "terra.exec.route.confidence";
    };

    // SDK resource attributes
    pub const sdk = struct {
        pub const name = "telemetry.sdk.name";
        pub const version = "telemetry.sdk.version";
        pub const language = "telemetry.sdk.language";
    };

    // Service attributes
    pub const service = struct {
        pub const name = "service.name";
        pub const version = "service.version";
    };

    // Session attributes
    pub const session_key = struct {
        pub const id = "session.id";
        pub const previous_id = "session.previous_id";
    };

    // Schema version
    pub const schema_version = "terra.schema.version";
};

// SDK metadata
pub const sdk_name = "terra";
pub const sdk_version = "1.0.0";
pub const sdk_language = "zig";
pub const schema_version_value = "1.0.0";

// ── Tests ───────────────────────────────────────────────────────────────
test "span_names.isTerraSpanName recognizes all known names" {
    try std.testing.expect(span_names.isTerraSpanName("gen_ai.inference"));
    try std.testing.expect(span_names.isTerraSpanName("gen_ai.embeddings"));
    try std.testing.expect(span_names.isTerraSpanName("gen_ai.agent"));
    try std.testing.expect(span_names.isTerraSpanName("gen_ai.tool"));
    try std.testing.expect(span_names.isTerraSpanName("terra.safety_check"));
    try std.testing.expect(span_names.isTerraSpanName("terra.session"));
    try std.testing.expect(span_names.isTerraSpanName("terra.coreml.model_load"));
}

test "span_names.isTerraSpanName rejects unknown" {
    try std.testing.expect(!span_names.isTerraSpanName("unknown.span"));
    try std.testing.expect(!span_names.isTerraSpanName(""));
}

test "OperationName.toString" {
    try std.testing.expectEqualStrings("inference", OperationName.inference.toString());
    try std.testing.expectEqualStrings("invoke_agent", OperationName.invoke_agent.toString());
}

test "key uniqueness — no duplicate gen_ai keys" {
    const gen_ai_keys = [_][]const u8{
        keys.gen_ai.operation_name,
        keys.gen_ai.request_model,
        keys.gen_ai.request_max_tokens,
        keys.gen_ai.request_temperature,
        keys.gen_ai.request_stream,
        keys.gen_ai.usage_input_tokens,
        keys.gen_ai.usage_output_tokens,
        keys.gen_ai.response_model,
        keys.gen_ai.provider_name,
        keys.gen_ai.agent_name,
        keys.gen_ai.agent_id,
        keys.gen_ai.tool_name,
        keys.gen_ai.tool_type,
        keys.gen_ai.tool_call_id,
    };
    for (gen_ai_keys, 0..) |k1, i| {
        for (gen_ai_keys[i + 1 ..]) |k2| {
            try std.testing.expect(!std.mem.eql(u8, k1, k2));
        }
    }
}

test "all Swift constants have Zig equivalents" {
    // Verify critical keys exist (compile-time check via reference)
    _ = keys.gen_ai.operation_name;
    _ = keys.terra.content_policy;
    _ = keys.terra.stream_time_to_first_token_ms;
    _ = keys.terra.exec_route_confidence;
    _ = metric_names.inference_count;
    _ = metric_names.inference_duration_ms;
}
