// Terra Zig Core — c_api.zig
// C ABI function implementations. All functions: null-safe, never panic, return terra_error_t or ?*Handle.

const std = @import("std");
const terra_mod = @import("terra.zig");
const config_mod = @import("config.zig");
const span_mod = @import("span.zig");
const models = @import("models.zig");
const privacy = @import("privacy.zig");
const transport_mod = @import("transport.zig");
const scheduler_mod = @import("scheduler.zig");
const storage_mod = @import("storage.zig");
const clock = @import("clock.zig");

const TerraInstance = terra_mod.TerraInstance;
const TerraConfig = config_mod.TerraConfig;
const Span = span_mod.Span;
const StreamingScope = span_mod.StreamingScope;
const SpanContext = models.SpanContext;
const SpanRecord = models.SpanRecord;
const TerraVersion = terra_mod.TerraVersion;

// ── Error codes matching terra.h ────────────────────────────────────────
pub const TERRA_OK: c_int = 0;
pub const TERRA_ERR_ALREADY_INITIALIZED: c_int = 1;
pub const TERRA_ERR_NOT_INITIALIZED: c_int = 2;
pub const TERRA_ERR_INVALID_CONFIG: c_int = 3;
pub const TERRA_ERR_OUT_OF_MEMORY: c_int = 4;
pub const TERRA_ERR_TRANSPORT_FAILED: c_int = 5;
pub const TERRA_ERR_SHUTTING_DOWN: c_int = 6;

// ── Last error (threadlocal for safe error reporting) ───────────────────
threadlocal var last_error_code: c_int = TERRA_OK;
threadlocal var last_error_msg: [256]u8 = [_]u8{0} ** 256;
threadlocal var last_error_msg_len: u8 = 0;

fn setLastError(code: c_int, msg: []const u8) void {
    last_error_code = code;
    const copy_len = @min(msg.len, @as(usize, 255));
    @memcpy(last_error_msg[0..copy_len], msg[0..copy_len]);
    last_error_msg_len = @intCast(copy_len);
}

// ── Lifecycle ───────────────────────────────────────────────────────────

pub export fn terra_init(config_ptr: ?*const TerraConfig) callconv(.c) ?*TerraInstance {
    const cfg = if (config_ptr) |c| c.* else TerraConfig.default();
    const allocator = cfg.allocator;

    return TerraInstance.create(allocator, cfg) catch |err| {
        switch (err) {
            error.InvalidConfig => setLastError(TERRA_ERR_INVALID_CONFIG, "Invalid configuration"),
            error.OutOfMemory => setLastError(TERRA_ERR_OUT_OF_MEMORY, "Out of memory"),
        }
        return null;
    };
}

pub export fn terra_shutdown(inst: ?*TerraInstance) callconv(.c) c_int {
    const i = inst orelse {
        setLastError(TERRA_ERR_NOT_INITIALIZED, "Instance is null");
        return TERRA_ERR_NOT_INITIALIZED;
    };
    i.destroy();
    return TERRA_OK;
}

pub export fn terra_get_state(inst: ?*const TerraInstance) callconv(.c) u8 {
    const i = inst orelse return 0;
    return @intFromEnum(i.state);
}

pub export fn terra_is_running(inst: ?*const TerraInstance) callconv(.c) bool {
    const i = inst orelse return false;
    return i.isRunning();
}

// ── Config ──────────────────────────────────────────────────────────────

pub export fn terra_set_session_id(inst: ?*TerraInstance, session_id: ?[*:0]const u8) callconv(.c) c_int {
    const i = inst orelse return TERRA_ERR_NOT_INITIALIZED;
    const sid = session_id orelse return TERRA_ERR_INVALID_CONFIG;
    i.setSessionId(std.mem.sliceTo(sid, 0));
    return TERRA_OK;
}

pub export fn terra_set_service_info(inst: ?*TerraInstance, name: ?[*:0]const u8, ver: ?[*:0]const u8) callconv(.c) c_int {
    const i = inst orelse return TERRA_ERR_NOT_INITIALIZED;
    const n = name orelse return TERRA_ERR_INVALID_CONFIG;
    const v = ver orelse return TERRA_ERR_INVALID_CONFIG;
    i.setServiceInfo(std.mem.sliceTo(n, 0), std.mem.sliceTo(v, 0));
    return TERRA_OK;
}

// ── Span creation (parent by context) ───────────────────────────────────

pub export fn terra_begin_inference_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, model: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const m = if (model) |m_ptr| std.mem.sliceTo(m_ptr, 0) else null;
    return i.beginInferenceSpan(ctx, m, include_content);
}

pub export fn terra_begin_embedding_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, model: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const m = if (model) |m_ptr| std.mem.sliceTo(m_ptr, 0) else null;
    return i.beginEmbeddingSpan(ctx, m, include_content);
}

pub export fn terra_begin_agent_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, agent_name: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const n = if (agent_name) |n_ptr| std.mem.sliceTo(n_ptr, 0) else null;
    return i.beginAgentSpan(ctx, n, include_content);
}

pub export fn terra_begin_tool_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, tool_name: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const n = if (tool_name) |n_ptr| std.mem.sliceTo(n_ptr, 0) else null;
    return i.beginToolSpan(ctx, n, include_content);
}

pub export fn terra_begin_safety_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, check_name: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const n = if (check_name) |n_ptr| std.mem.sliceTo(n_ptr, 0) else null;
    return i.beginSafetySpan(ctx, n, include_content);
}

pub export fn terra_begin_streaming_span_ctx(inst: ?*TerraInstance, parent_ctx: ?*const SpanContext, model: ?[*:0]const u8, include_content: bool) callconv(.c) ?*Span {
    const i = inst orelse return null;
    const ctx = if (parent_ctx) |p| p.* else null;
    const m = if (model) |m_ptr| std.mem.sliceTo(m_ptr, 0) else null;
    return i.beginStreamingSpan(ctx, m, include_content);
}

// ── Span mutation ───────────────────────────────────────────────────────

pub export fn terra_span_set_string(s: ?*Span, key: ?[*:0]const u8, value: ?[*:0]const u8) callconv(.c) void {
    const span = s orelse return;
    const k = key orelse return;
    const v = value orelse return;
    span.setString(std.mem.sliceTo(k, 0), std.mem.sliceTo(v, 0));
}

pub export fn terra_span_set_int(s: ?*Span, key: ?[*:0]const u8, value: i64) callconv(.c) void {
    const span = s orelse return;
    const k = key orelse return;
    span.setInt(std.mem.sliceTo(k, 0), value);
}

pub export fn terra_span_set_double(s: ?*Span, key: ?[*:0]const u8, value: f64) callconv(.c) void {
    const span = s orelse return;
    const k = key orelse return;
    span.setDouble(std.mem.sliceTo(k, 0), value);
}

pub export fn terra_span_set_bool(s: ?*Span, key: ?[*:0]const u8, value: bool) callconv(.c) void {
    const span = s orelse return;
    const k = key orelse return;
    span.setBool(std.mem.sliceTo(k, 0), value);
}

pub export fn terra_span_set_status(s: ?*Span, status_code: u8, description: ?[*:0]const u8) callconv(.c) void {
    const span = s orelse return;
    const code = std.meta.intToEnum(models.StatusCode, status_code) catch return;
    const desc = if (description) |d| std.mem.sliceTo(d, 0) else null;
    span.setStatus(code, desc);
}

pub export fn terra_span_end(inst: ?*TerraInstance, s: ?*Span) callconv(.c) void {
    const i = inst orelse return;
    const span = s orelse return;
    i.endSpan(span);
}

// ── Events ──────────────────────────────────────────────────────────────

pub export fn terra_span_add_event(s: ?*Span, name: ?[*:0]const u8) callconv(.c) void {
    const span = s orelse return;
    const n = name orelse return;
    span.addEvent(std.mem.sliceTo(n, 0));
}

pub export fn terra_span_add_event_ts(s: ?*Span, name: ?[*:0]const u8, timestamp_ns: u64) callconv(.c) void {
    const span = s orelse return;
    const n = name orelse return;
    span.addEventTs(std.mem.sliceTo(n, 0), timestamp_ns);
}

// ── Error recording ─────────────────────────────────────────────────────

pub export fn terra_span_record_error(s: ?*Span, error_type: ?[*:0]const u8, error_message: ?[*:0]const u8, set_status: bool) callconv(.c) void {
    const span = s orelse return;
    const et = error_type orelse return;
    const em = error_message orelse return;
    span.recordError(std.mem.sliceTo(et, 0), std.mem.sliceTo(em, 0), set_status);
}

// ── Streaming ───────────────────────────────────────────────────────────
// Note: StreamingScope is stack-allocated by the caller. These C API functions
// operate on a Span directly for simplicity.

pub export fn terra_streaming_record_token(s: ?*Span) callconv(.c) void {
    const span = s orelse return;
    span.addEvent("terra.token");
}

pub export fn terra_streaming_record_first_token(s: ?*Span) callconv(.c) void {
    const span = s orelse return;
    span.addEvent("terra.first_token");
}

pub export fn terra_streaming_end(s: ?*Span) callconv(.c) void {
    const span = s orelse return;
    span.addEvent("terra.stream.end");
}

// ── Context extraction ──────────────────────────────────────────────────

pub export fn terra_span_context(s: ?*const Span) callconv(.c) SpanContext {
    const span = s orelse return SpanContext.invalid;
    return TerraInstance.spanContext(span);
}

// ── Diagnostics ─────────────────────────────────────────────────────────

pub export fn terra_last_error() callconv(.c) c_int {
    return last_error_code;
}

pub export fn terra_last_error_message(buf: ?[*]u8, max_len: u32) callconv(.c) u32 {
    const b = buf orelse return 0;
    const copy_len = @min(@as(u32, last_error_msg_len), max_len);
    @memcpy(b[0..copy_len], last_error_msg[0..copy_len]);
    return copy_len;
}

pub export fn terra_spans_dropped(inst: ?*const TerraInstance) callconv(.c) u64 {
    const i = inst orelse return 0;
    return i.spansDropped();
}

pub export fn terra_transport_degraded(inst: ?*const TerraInstance) callconv(.c) bool {
    const i = inst orelse return false;
    return i.metrics.transport_errors.get() > 0;
}

// ── Version ─────────────────────────────────────────────────────────────

pub export fn terra_get_version() callconv(.c) TerraVersion {
    return terra_mod.version;
}

// ── Test support ────────────────────────────────────────────────────────

pub export fn terra_test_drain_spans(inst: ?*TerraInstance, out_buf: ?[*]SpanRecord, max: u32) callconv(.c) u32 {
    const i = inst orelse return 0;
    const buf = out_buf orelse return 0;
    return i.drainSpans(buf[0..max]);
}

pub export fn terra_test_reset(inst: ?*TerraInstance) callconv(.c) void {
    const i = inst orelse return;
    i.reset();
}

// ── Metrics ─────────────────────────────────────────────────────────────

pub export fn terra_record_inference_duration(inst: ?*TerraInstance, duration_ms: f64) callconv(.c) void {
    const i = inst orelse return;
    i.metrics.inference_duration_ms.record(duration_ms);
    i.metrics.inference_count.increment();
}

pub export fn terra_record_token_count(inst: ?*TerraInstance, input_tokens: i64, output_tokens: i64) callconv(.c) void {
    const i = inst orelse return;
    if (input_tokens > 0) i.metrics.input_tokens_total.add(input_tokens);
    if (output_tokens > 0) i.metrics.output_tokens_total.add(output_tokens);
}

// ── Tests ───────────────────────────────────────────────────────────────
test "terra_init and terra_shutdown" {
    const inst = terra_init(null);
    try std.testing.expect(inst != null);
    try std.testing.expect(terra_is_running(inst));

    const result = terra_shutdown(inst);
    try std.testing.expectEqual(TERRA_OK, result);
}

test "terra_init null returns default instance" {
    const inst = terra_init(null);
    try std.testing.expect(inst != null);
    _ = terra_shutdown(inst);
}

test "terra_shutdown null returns error" {
    const result = terra_shutdown(null);
    try std.testing.expectEqual(TERRA_ERR_NOT_INITIALIZED, result);
}

test "terra_span lifecycle via C API" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const span = terra_begin_inference_span_ctx(inst, null, "gpt-4", false);
    try std.testing.expect(span != null);

    terra_span_set_string(span, "key", "value");
    terra_span_set_int(span, "tokens", 100);
    terra_span_set_double(span, "temp", 0.7);
    terra_span_set_bool(span, "stream", true);
    terra_span_set_status(span, 1, "ok");
    terra_span_add_event(span, "started");
    terra_span_record_error(span, "RuntimeError", "test error", false);

    terra_span_end(inst, span);
}

test "terra_span_context extraction" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const span = terra_begin_inference_span_ctx(inst, null, "model", false).?;
    const ctx = terra_span_context(span);
    try std.testing.expect(ctx.isValid());

    // Use context as parent
    const child = terra_begin_tool_span_ctx(inst, &ctx, "tool", false);
    try std.testing.expect(child != null);

    terra_span_end(inst, child);
    terra_span_end(inst, span);
}

test "terra_test_drain_spans and terra_test_reset" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const span = terra_begin_inference_span_ctx(inst, null, "model", false).?;
    terra_span_end(inst, span);

    var buf: [4]SpanRecord = undefined;
    const count = terra_test_drain_spans(inst, &buf, 4);
    try std.testing.expectEqual(@as(u32, 1), count);

    terra_test_reset(inst);
    const count2 = terra_test_drain_spans(inst, &buf, 4);
    try std.testing.expectEqual(@as(u32, 0), count2);
}

test "terra_get_version" {
    const v = terra_get_version();
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 0), v.minor);
}

test "terra_last_error" {
    _ = terra_shutdown(null); // Sets error
    try std.testing.expectEqual(TERRA_ERR_NOT_INITIALIZED, terra_last_error());

    var msg_buf: [256]u8 = undefined;
    const len = terra_last_error_message(&msg_buf, 256);
    try std.testing.expect(len > 0);
}

test "terra_set_session_id" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const result = terra_set_session_id(inst, "session-123");
    try std.testing.expectEqual(TERRA_OK, result);
}

test "terra_set_service_info" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const result = terra_set_service_info(inst, "my-app", "2.0.0");
    try std.testing.expectEqual(TERRA_OK, result);
}

test "all 6 span types via C API" {
    const inst = terra_init(null).?;
    defer _ = terra_shutdown(inst);

    const spans = [_]?*Span{
        terra_begin_inference_span_ctx(inst, null, "m", false),
        terra_begin_embedding_span_ctx(inst, null, "m", false),
        terra_begin_agent_span_ctx(inst, null, "a", false),
        terra_begin_tool_span_ctx(inst, null, "t", false),
        terra_begin_safety_span_ctx(inst, null, "c", false),
        terra_begin_streaming_span_ctx(inst, null, "m", false),
    };

    for (&spans) |maybe_s| {
        try std.testing.expect(maybe_s != null);
        terra_span_end(inst, maybe_s);
    }

    var buf: [8]SpanRecord = undefined;
    const count = terra_test_drain_spans(inst, &buf, 8);
    try std.testing.expectEqual(@as(u32, 6), count);
}

test "null-safety — all C API functions handle null gracefully" {
    terra_span_set_string(null, null, null);
    terra_span_set_int(null, null, 0);
    terra_span_set_double(null, null, 0);
    terra_span_set_bool(null, null, false);
    terra_span_set_status(null, 0, null);
    terra_span_end(null, null);
    terra_span_add_event(null, null);
    terra_span_add_event_ts(null, null, 0);
    terra_span_record_error(null, null, null, false);
    terra_streaming_record_token(null);
    terra_streaming_record_first_token(null);
    terra_streaming_end(null);
    _ = terra_span_context(null);
    _ = terra_spans_dropped(null);
    _ = terra_transport_degraded(null);
    _ = terra_test_drain_spans(null, null, 0);
    terra_test_reset(null);
    _ = terra_set_session_id(null, null);
    _ = terra_set_service_info(null, null, null);
}
