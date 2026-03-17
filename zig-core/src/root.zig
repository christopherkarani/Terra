// Terra Zig Core — Library root
// Re-exports all public modules for the library target.

pub const models = @import("models.zig");
pub const constants = @import("constants.zig");
pub const clock = @import("clock.zig");
pub const privacy = @import("privacy.zig");
pub const config = @import("config.zig");
pub const span = @import("span.zig");
pub const store = @import("store.zig");
pub const transport = @import("transport.zig");
pub const http_transport = @import("http_transport.zig");
pub const coap_transport = @import("coap_transport.zig");
pub const shm_transport = @import("shm_transport.zig");
pub const uart_transport = @import("uart_transport.zig");
pub const mqtt_transport = @import("mqtt_transport.zig");
pub const file_storage = @import("file_storage.zig");
pub const scheduler = @import("scheduler.zig");
pub const storage = @import("storage.zig");
pub const metrics = @import("metrics.zig");
pub const otlp = @import("otlp.zig");
pub const processor = @import("processor.zig");
pub const resource = @import("resource.zig");
pub const terra = @import("terra.zig");
pub const c_api = @import("c_api.zig");
pub const test_harness = @import("test_harness.zig");

// Force C ABI exports to be retained in the static library.
// Without this, Zig's dead-code elimination strips the `export fn` symbols
// because nothing within the library itself references them.
comptime {
    _ = &c_api.terra_init;
    _ = &c_api.terra_shutdown;
    _ = &c_api.terra_get_state;
    _ = &c_api.terra_is_running;
    _ = &c_api.terra_set_session_id;
    _ = &c_api.terra_set_service_info;
    _ = &c_api.terra_begin_inference_span_ctx;
    _ = &c_api.terra_begin_embedding_span_ctx;
    _ = &c_api.terra_begin_agent_span_ctx;
    _ = &c_api.terra_begin_tool_span_ctx;
    _ = &c_api.terra_begin_safety_span_ctx;
    _ = &c_api.terra_begin_streaming_span_ctx;
    _ = &c_api.terra_span_set_string;
    _ = &c_api.terra_span_set_int;
    _ = &c_api.terra_span_set_double;
    _ = &c_api.terra_span_set_bool;
    _ = &c_api.terra_span_set_status;
    _ = &c_api.terra_span_end;
    _ = &c_api.terra_span_add_event;
    _ = &c_api.terra_span_add_event_ts;
    _ = &c_api.terra_span_record_error;
    _ = &c_api.terra_streaming_record_token;
    _ = &c_api.terra_streaming_record_first_token;
    _ = &c_api.terra_streaming_end;
    _ = &c_api.terra_span_context;
    _ = &c_api.terra_last_error;
    _ = &c_api.terra_last_error_message;
    _ = &c_api.terra_spans_dropped;
    _ = &c_api.terra_transport_degraded;
    _ = &c_api.terra_get_version;
    _ = &c_api.terra_record_inference_duration;
    _ = &c_api.terra_record_token_count;
    _ = &c_api.terra_test_drain_spans;
    _ = &c_api.terra_test_reset;
}

// Re-export primary public types at top level for convenience
pub const TerraInstance = terra.TerraInstance;
pub const TerraConfig = config.TerraConfig;
pub const Span = span.Span;
pub const SpanRecord = models.SpanRecord;
pub const TraceID = models.TraceID;
pub const SpanID = models.SpanID;
pub const SpanContext = models.SpanContext;

test {
    // Pull in all module tests
    @import("std").testing.refAllDecls(@This());
}
