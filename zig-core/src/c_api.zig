// Terra Zig Core — c_api.zig
// C ABI function implementations. All functions: null-safe, never panic, return terra_error_t or ?*Handle.

const std = @import("std");
const builtin = @import("builtin");
const terra_mod = @import("terra.zig");
const config_mod = @import("config.zig");
const span_mod = @import("span.zig");
const models = @import("models.zig");
const privacy = @import("privacy.zig");
const transport_mod = @import("transport.zig");
const mqtt_transport = @import("mqtt_transport.zig");
const coap_transport = @import("coap_transport.zig");
const uart_transport = @import("uart_transport.zig");
const scheduler_mod = @import("scheduler.zig");
const storage_mod = @import("storage.zig");
const clock = @import("clock.zig");
const constants = @import("constants.zig");

const TerraInstance = terra_mod.TerraInstance;
const TerraConfig = config_mod.TerraConfig;
const Span = span_mod.Span;
const StreamingScope = span_mod.StreamingScope;
const SpanContext = models.SpanContext;
const SpanRecord = models.SpanRecord;
const TerraVersion = terra_mod.TerraVersion;

const CClockFn = ?*const fn (?*anyopaque) callconv(.c) u64;
const CSendFn = ?*const fn ([*]const u8, u32, ?*anyopaque) callconv(.c) c_int;
const CFlushFn = ?*const fn (?*anyopaque) callconv(.c) void;
const CShutdownFn = ?*const fn (?*anyopaque) callconv(.c) void;
const CSchedulerCallbackFn = ?*const fn (?*anyopaque) callconv(.c) void;
const CScheduleFn = ?*const fn (CSchedulerCallbackFn, u64, ?*anyopaque, ?*anyopaque) callconv(.c) u64;
const CCancelFn = ?*const fn (u64, ?*anyopaque) callconv(.c) void;
const CStorageWriteFn = ?*const fn ([*]const u8, u32, ?*anyopaque) callconv(.c) c_int;
const CStorageReadFn = ?*const fn ([*]u8, u32, ?*anyopaque) callconv(.c) u32;
const CStorageDiscardOldestFn = ?*const fn (u32, ?*anyopaque) callconv(.c) void;
const CStorageAvailableBytesFn = ?*const fn (?*anyopaque) callconv(.c) u64;
const CMqttPublishFn = ?*const fn ([*:0]const u8, [*]const u8, u32, u8, ?*anyopaque) callconv(.c) c_int;
const CUdpSendFn = ?*const fn ([*]const u8, u32, ?*anyopaque) callconv(.c) c_int;

pub const TestSpanRecord = extern struct {
    trace_id_hi: u64 = 0,
    trace_id_lo: u64 = 0,
    span_id: u64 = 0,
    parent_span_id: u64 = 0,
    name: [models.MAX_SPAN_NAME]u8 = [_]u8{0} ** models.MAX_SPAN_NAME,
    name_len: u8 = 0,
    kind: u8 = 0,
    status: u8 = 0,
    start_time_ns: u64 = 0,
    end_time_ns: u64 = 0,
};
const CUartWriteFn = ?*const fn ([*]const u8, u32, ?*anyopaque) callconv(.c) c_int;

const CTerraTransportVTable = extern struct {
    send_fn: CSendFn = null,
    flush_fn: CFlushFn = null,
    shutdown_fn: CShutdownFn = null,
    context: ?*anyopaque = null,
};

const CTerraSchedulerVTable = extern struct {
    schedule_fn: CScheduleFn = null,
    cancel_fn: CCancelFn = null,
    context: ?*anyopaque = null,
};

const CTerraStorageVTable = extern struct {
    write_fn: CStorageWriteFn = null,
    read_fn: CStorageReadFn = null,
    discard_oldest_fn: CStorageDiscardOldestFn = null,
    available_bytes_fn: CStorageAvailableBytesFn = null,
    context: ?*anyopaque = null,
};

const CTerraMqttTransportConfig = extern struct {
    broker_host: ?[*:0]const u8 = null,
    broker_port: u16 = 1883,
    topic: ?[*:0]const u8 = null,
    client_id: ?[*:0]const u8 = null,
    qos: u8 = mqtt_transport.DEFAULT_QOS,
    publish_fn: CMqttPublishFn = null,
    publish_ctx: ?*anyopaque = null,
};

const CTerraCoapTransportConfig = extern struct {
    udp_send_fn: CUdpSendFn = null,
    udp_ctx: ?*anyopaque = null,
    next_message_id: u16 = 1,
};

const CTerraUartTransportConfig = extern struct {
    uart_write_fn: CUartWriteFn = null,
    uart_ctx: ?*anyopaque = null,
};

const CTerraConfig = extern struct {
    max_spans: u32 = 0,
    max_attributes_per_span: u16 = 0,
    max_events_per_span: u16 = 0,
    max_event_attrs: u16 = 0,
    batch_size: u32 = 0,
    flush_interval_ms: u64 = 0,
    content_policy: c_int = 0,
    redaction_strategy: c_int = 0,
    hmac_key: ?[*:0]const u8 = null,
    emit_legacy_sha256: bool = false,
    service_name: ?[*:0]const u8 = null,
    service_version: ?[*:0]const u8 = null,
    otlp_endpoint: ?[*:0]const u8 = null,
    clock_fn: CClockFn = null,
    clock_ctx: ?*anyopaque = null,
    transport_vtable: CTerraTransportVTable = .{},
    scheduler_vtable: CTerraSchedulerVTable = .{},
    storage_vtable: CTerraStorageVTable = .{},
};

// ── Error codes matching terra.h ────────────────────────────────────────
pub const TERRA_OK: c_int = 0;
pub const TERRA_ERR_ALREADY_INITIALIZED: c_int = 1;
pub const TERRA_ERR_NOT_INITIALIZED: c_int = 2;
pub const TERRA_ERR_INVALID_CONFIG: c_int = 3;
pub const TERRA_ERR_OUT_OF_MEMORY: c_int = 4;
pub const TERRA_ERR_TRANSPORT_FAILED: c_int = 5;
pub const TERRA_ERR_SHUTTING_DOWN: c_int = 6;

// Zig's x86_64 Android TLS path pulls in __tls_get_addr when linked into the
// NDK-built JNI bridge. Avoid TLS there so emulator builds link cleanly.
const use_threadlocal_errors = !(builtin.abi == .android and builtin.cpu.arch == .x86_64);

threadlocal var tls_last_error_code: c_int = TERRA_OK;
threadlocal var tls_last_error_msg: [256]u8 = [_]u8{0} ** 256;
threadlocal var tls_last_error_msg_len: u8 = 0;

var global_last_error_lock: std.Thread.Mutex = .{};
var global_last_error_code: c_int = TERRA_OK;
var global_last_error_msg: [256]u8 = [_]u8{0} ** 256;
var global_last_error_msg_len: u8 = 0;

inline fn lastErrorCodePtr() *c_int {
    return if (use_threadlocal_errors) &tls_last_error_code else &global_last_error_code;
}

inline fn lastErrorMsgPtr() *[256]u8 {
    return if (use_threadlocal_errors) &tls_last_error_msg else &global_last_error_msg;
}

inline fn lastErrorMsgLenPtr() *u8 {
    return if (use_threadlocal_errors) &tls_last_error_msg_len else &global_last_error_msg_len;
}

fn setLastError(code: c_int, msg: []const u8) void {
    if (!use_threadlocal_errors) {
        global_last_error_lock.lock();
        defer global_last_error_lock.unlock();
    }

    lastErrorCodePtr().* = code;
    const copy_len = @min(msg.len, @as(usize, 255));
    const last_error_msg = lastErrorMsgPtr();
    @memset(last_error_msg, 0);
    @memcpy(last_error_msg[0..copy_len], msg[0..copy_len]);
    lastErrorMsgLenPtr().* = @intCast(copy_len);
}

fn mapContentPolicy(raw: c_int) !privacy.ContentPolicy {
    return switch (raw) {
        0 => .never,
        1 => .opt_in,
        2 => .always,
        else => error.InvalidConfig,
    };
}

fn mapRedactionStrategy(raw: c_int) !privacy.RedactionStrategy {
    return switch (raw) {
        0 => .drop,
        1 => .length_only,
        2 => .hmac_sha256,
        3 => .sha256,
        else => error.InvalidConfig,
    };
}

fn toTransportVTable(vtable: CTerraTransportVTable) transport_mod.TransportVTable {
    return .{
        .send_fn = vtable.send_fn orelse transport_mod.noop_transport.send_fn,
        .flush_fn = vtable.flush_fn orelse transport_mod.noop_transport.flush_fn,
        .shutdown_fn = vtable.shutdown_fn orelse transport_mod.noop_transport.shutdown_fn,
        .context = vtable.context,
    };
}

fn noopCTransportVTable() CTerraTransportVTable {
    return .{
        .send_fn = transport_mod.noop_transport.send_fn,
        .flush_fn = transport_mod.noop_transport.flush_fn,
        .shutdown_fn = transport_mod.noop_transport.shutdown_fn,
        .context = null,
    };
}

fn mqttCSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *CTerraMqttTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));
    const publish = cfg.publish_fn orelse return -1;
    if (cfg.qos > mqtt_transport.QOS_EXACTLY_ONCE) return -1;

    const topic = cfg.topic orelse mqtt_transport.DEFAULT_TOPIC.ptr;
    if (topic[0] == 0) return -1;

    return publish(topic, data, len, cfg.qos, cfg.publish_ctx);
}

fn mqttCFlush(_: ?*anyopaque) callconv(.c) void {}
fn mqttCShutdown(_: ?*anyopaque) callconv(.c) void {}

fn coapCSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *CTerraCoapTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));
    const udp_send = cfg.udp_send_fn orelse return -1;

    const message_id = @atomicRmw(u16, &cfg.next_message_id, .Add, 1, .seq_cst);
    var frame_buf: [2048]u8 = undefined;
    const frame = coap_transport.buildTraceFrame(data[0..len], message_id, &frame_buf) orelse return -1;
    return udp_send(frame.ptr, @intCast(frame.len), cfg.udp_ctx);
}

fn coapCFlush(_: ?*anyopaque) callconv(.c) void {}
fn coapCShutdown(_: ?*anyopaque) callconv(.c) void {}

fn uartCSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *CTerraUartTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));
    const write = cfg.uart_write_fn orelse return -1;

    var frame_buf: [uart_transport.FRAME_OVERHEAD + uart_transport.MAX_PAYLOAD_SIZE]u8 = undefined;
    const frame = uart_transport.buildFrame(data[0..len], &frame_buf) orelse return -1;
    return write(frame.ptr, @intCast(frame.len), cfg.uart_ctx);
}

fn uartCFlush(_: ?*anyopaque) callconv(.c) void {}
fn uartCShutdown(_: ?*anyopaque) callconv(.c) void {}

pub export fn terra_transport_mqtt(config: ?*CTerraMqttTransportConfig) callconv(.c) CTerraTransportVTable {
    const cfg = config orelse return noopCTransportVTable();
    return .{
        .send_fn = mqttCSend,
        .flush_fn = mqttCFlush,
        .shutdown_fn = mqttCShutdown,
        .context = cfg,
    };
}

pub export fn terra_transport_coap(config: ?*CTerraCoapTransportConfig) callconv(.c) CTerraTransportVTable {
    const cfg = config orelse return noopCTransportVTable();
    return .{
        .send_fn = coapCSend,
        .flush_fn = coapCFlush,
        .shutdown_fn = coapCShutdown,
        .context = cfg,
    };
}

pub export fn terra_transport_uart(config: ?*CTerraUartTransportConfig) callconv(.c) CTerraTransportVTable {
    const cfg = config orelse return noopCTransportVTable();
    return .{
        .send_fn = uartCSend,
        .flush_fn = uartCFlush,
        .shutdown_fn = uartCShutdown,
        .context = cfg,
    };
}

fn toSchedulerVTable(vtable: CTerraSchedulerVTable) scheduler_mod.SchedulerVTable {
    return .{
        .schedule_fn = vtable.schedule_fn orelse scheduler_mod.noop_scheduler.schedule_fn,
        .cancel_fn = vtable.cancel_fn orelse scheduler_mod.noop_scheduler.cancel_fn,
        .context = vtable.context,
    };
}

fn toStorageVTable(vtable: CTerraStorageVTable) storage_mod.StorageVTable {
    return .{
        .write_fn = vtable.write_fn orelse storage_mod.noop_storage.write_fn,
        .read_fn = vtable.read_fn orelse storage_mod.noop_storage.read_fn,
        .discard_oldest_fn = vtable.discard_oldest_fn orelse storage_mod.noop_storage.discard_oldest_fn,
        .available_bytes_fn = vtable.available_bytes_fn orelse storage_mod.noop_storage.available_bytes_fn,
        .context = vtable.context,
    };
}

fn translateConfig(c_cfg: CTerraConfig) !TerraConfig {
    var cfg = TerraConfig.default();

    if (c_cfg.max_spans != 0) cfg.max_spans = c_cfg.max_spans;
    if (c_cfg.max_attributes_per_span != 0) cfg.max_attributes_per_span = c_cfg.max_attributes_per_span;
    if (c_cfg.max_events_per_span != 0) cfg.max_events_per_span = c_cfg.max_events_per_span;
    if (c_cfg.max_event_attrs != 0) cfg.max_event_attrs = c_cfg.max_event_attrs;
    if (c_cfg.batch_size != 0) cfg.batch_size = c_cfg.batch_size;
    if (c_cfg.flush_interval_ms != 0) cfg.flush_interval_ms = c_cfg.flush_interval_ms;

    cfg.content_policy = try mapContentPolicy(c_cfg.content_policy);
    cfg.redaction_strategy = try mapRedactionStrategy(c_cfg.redaction_strategy);
    cfg.hmac_key = c_cfg.hmac_key;
    cfg.emit_legacy_sha256 = c_cfg.emit_legacy_sha256;

    if (c_cfg.service_name) |service_name| cfg.service_name = service_name;
    if (c_cfg.service_version) |service_version| cfg.service_version = service_version;
    if (c_cfg.otlp_endpoint) |otlp_endpoint| cfg.otlp_endpoint = otlp_endpoint;

    cfg.clock_fn = c_cfg.clock_fn orelse clock.stdClock;
    cfg.clock_ctx = c_cfg.clock_ctx;
    cfg.transport_vtable = toTransportVTable(c_cfg.transport_vtable);
    cfg.scheduler_vtable = toSchedulerVTable(c_cfg.scheduler_vtable);
    cfg.storage_vtable = toStorageVTable(c_cfg.storage_vtable);

    if (c_cfg.batch_size == 0 and cfg.batch_size > cfg.max_spans) {
        cfg.batch_size = cfg.max_spans;
    }

    return cfg;
}

// ── Lifecycle ───────────────────────────────────────────────────────────

pub export fn terra_init(config_ptr: ?*const CTerraConfig) callconv(.c) ?*TerraInstance {
    const cfg = if (config_ptr) |c| translateConfig(c.*) else TerraConfig.default();
    const resolved_cfg = cfg catch |err| {
        switch (err) {
            error.InvalidConfig => setLastError(TERRA_ERR_INVALID_CONFIG, "Invalid configuration"),
        }
        return null;
    };
    const allocator = resolved_cfg.allocator;

    return TerraInstance.create(allocator, resolved_cfg) catch |err| {
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
    if (!use_threadlocal_errors) {
        global_last_error_lock.lock();
        defer global_last_error_lock.unlock();
    }
    return lastErrorCodePtr().*;
}

pub export fn terra_last_error_message(buf: ?[*]u8, max_len: u32) callconv(.c) u32 {
    const b = buf orelse return 0;
    if (!use_threadlocal_errors) {
        global_last_error_lock.lock();
        defer global_last_error_lock.unlock();
    }
    const last_error_msg_len = lastErrorMsgLenPtr().*;
    const last_error_msg = lastErrorMsgPtr();
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

pub export fn terra_test_drain_spans(inst: ?*TerraInstance, out_buf: ?[*]TestSpanRecord, max: u32) callconv(.c) u32 {
    const i = inst orelse return 0;
    const buf = out_buf orelse return 0;
    if (max == 0) return 0;

    const capacity: usize = @intCast(max);
    const allocator = std.heap.page_allocator;
    const internal = allocator.alloc(SpanRecord, capacity) catch return 0;
    defer allocator.free(internal);

    const count = i.drainSpans(internal[0..capacity]);
    const written: usize = @intCast(count);
    for (internal[0..written], buf[0..written]) |source, *dest| {
        copyTestSpanRecord(&source, dest);
    }
    return count;
}

fn drainInternalSpansForTest(inst: ?*TerraInstance, out_buf: []SpanRecord) u32 {
    const i = inst orelse return 0;
    return i.drainSpans(out_buf);
}

fn copyTestSpanRecord(source: *const SpanRecord, dest: *TestSpanRecord) void {
    dest.* = .{};
    dest.trace_id_hi = source.trace_id.hi;
    dest.trace_id_lo = source.trace_id.lo;
    dest.span_id = source.span_id.id;
    dest.parent_span_id = source.parent_span_id.id;
    dest.kind = @intFromEnum(source.kind);
    dest.status = @intFromEnum(source.status);
    dest.start_time_ns = source.start_time_ns;
    dest.end_time_ns = source.end_time_ns;

    const copy_len = @min(@as(usize, source.name_len), dest.name.len);
    if (copy_len > 0) {
        @memcpy(dest.name[0..copy_len], source.name[0..copy_len]);
    }
    dest.name_len = @intCast(copy_len);
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

test "terra_init translates C config into internal config" {
    const raw = CTerraConfig{
        .max_spans = 32,
        .max_attributes_per_span = 16,
        .max_events_per_span = 4,
        .max_event_attrs = 2,
        .batch_size = 8,
        .flush_interval_ms = 250,
        .content_policy = 1,
        .redaction_strategy = 2,
        .service_name = "ffi-service",
        .service_version = "9.9.9",
        .otlp_endpoint = "http://collector.example:4318",
    };

    const inst = terra_init(&raw).?;
    defer _ = terra_shutdown(inst);

    try std.testing.expectEqual(@as(u32, 32), inst.config.max_spans);
    try std.testing.expectEqual(@as(u16, 16), inst.config.max_attributes_per_span);
    try std.testing.expectEqual(@as(u16, 4), inst.config.max_events_per_span);
    try std.testing.expectEqual(@as(u16, 2), inst.config.max_event_attrs);
    try std.testing.expectEqual(@as(u32, 8), inst.config.batch_size);
    try std.testing.expectEqual(@as(u64, 250), inst.config.flush_interval_ms);
    try std.testing.expectEqual(privacy.ContentPolicy.opt_in, inst.config.content_policy);
    try std.testing.expectEqual(privacy.RedactionStrategy.hmac_sha256, inst.config.redaction_strategy);
    try std.testing.expectEqualStrings("ffi-service", std.mem.sliceTo(inst.config.service_name, 0));
    try std.testing.expectEqualStrings("9.9.9", std.mem.sliceTo(inst.config.service_version, 0));
    try std.testing.expectEqualStrings("http://collector.example:4318", std.mem.sliceTo(inst.config.otlp_endpoint, 0));
}

test "terra_init applies defaults and clamps implicit batch size" {
    const raw = CTerraConfig{
        .max_spans = 64,
        .service_name = "partial-service",
    };

    const inst = terra_init(&raw).?;
    defer _ = terra_shutdown(inst);

    try std.testing.expectEqual(@as(u32, 64), inst.config.max_spans);
    try std.testing.expectEqual(@as(u16, 64), inst.config.max_attributes_per_span);
    try std.testing.expectEqual(@as(u16, 8), inst.config.max_events_per_span);
    try std.testing.expectEqual(@as(u16, 4), inst.config.max_event_attrs);
    try std.testing.expectEqual(@as(u32, 64), inst.config.batch_size);
    try std.testing.expectEqual(@as(u64, 5000), inst.config.flush_interval_ms);
    try std.testing.expectEqualStrings("partial-service", std.mem.sliceTo(inst.config.service_name, 0));
    try std.testing.expectEqualStrings("0.0.0", std.mem.sliceTo(inst.config.service_version, 0));
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

fn cStringBuffer(comptime size: usize, value: []const u8) [size:0]u8 {
    var buf: [size:0]u8 = undefined;
    @memset(buf[0..], 0);
    @memcpy(buf[0..value.len], value);
    return buf;
}

fn poisonCStringBuffer(buf: []u8, value_len: usize) void {
    @memset(buf[0..value_len], 'x');
}

fn findStringAttr(rec: *const SpanRecord, key: []const u8) ?[]const u8 {
    for (rec.attributes.slice()) |attr| {
        if (std.mem.eql(u8, attr.key, key)) {
            return switch (attr.value) {
                .string => |s| s,
                else => null,
            };
        }
    }
    return null;
}

test "C API span strings survive temporary caller buffers" {
    const raw = CTerraConfig{ .content_policy = 1 };
    const inst = terra_init(&raw).?;
    defer _ = terra_shutdown(inst);

    var model = cStringBuffer(64, "borrowed-model");
    const span = terra_begin_inference_span_ctx(inst, null, &model, true).?;
    poisonCStringBuffer(model[0..], "borrowed-model".len);

    var key = cStringBuffer(64, "dynamic.key");
    var value = cStringBuffer(64, "dynamic-value");
    terra_span_set_string(span, &key, &value);
    poisonCStringBuffer(key[0..], "dynamic.key".len);
    poisonCStringBuffer(value[0..], "dynamic-value".len);

    var event = cStringBuffer(64, "dynamic.event");
    terra_span_add_event(span, &event);
    poisonCStringBuffer(event[0..], "dynamic.event".len);

    var error_type = cStringBuffer(64, "DynamicError");
    var error_message = cStringBuffer(64, "temporary error message");
    terra_span_record_error(span, &error_type, &error_message, true);
    poisonCStringBuffer(error_type[0..], "DynamicError".len);
    poisonCStringBuffer(error_message[0..], "temporary error message".len);

    terra_span_end(inst, span);

    var buf: [4]SpanRecord = undefined;
    const count = drainInternalSpansForTest(inst, &buf);
    try std.testing.expectEqual(@as(u32, 1), count);

    try std.testing.expectEqualStrings("borrowed-model", findStringAttr(&buf[0], constants.keys.gen_ai.request_model).?);
    try std.testing.expectEqualStrings("dynamic-value", findStringAttr(&buf[0], "dynamic.key").?);
    try std.testing.expectEqualStrings("dynamic.event", buf[0].events[0].name);
    try std.testing.expectEqualStrings("DynamicError", buf[0].events[1].attributes.slice()[0].value.string);
    try std.testing.expectEqualStrings("temporary error message", buf[0].events[1].attributes.slice()[1].value.string);
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

    var buf: [4]TestSpanRecord = undefined;
    const count = terra_test_drain_spans(inst, &buf, 4);
    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqualStrings("gen_ai.inference", buf[0].name[0..buf[0].name_len]);

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

test "C API MQTT transport helper forwards payload through caller callback" {
    const TestCtx = struct {
        var called: bool = false;
        var qos: u8 = 0;
        var len: u32 = 0;
        var topic: ?[]const u8 = null;
    };
    TestCtx.called = false;
    TestCtx.qos = 0;
    TestCtx.len = 0;
    TestCtx.topic = null;

    var cfg = CTerraMqttTransportConfig{
        .topic = "/terra/robot/traces",
        .qos = 1,
        .publish_fn = struct {
            fn publish(topic: [*:0]const u8, _: [*]const u8, len: u32, qos: u8, _: ?*anyopaque) callconv(.c) c_int {
                TestCtx.called = true;
                TestCtx.qos = qos;
                TestCtx.len = len;
                TestCtx.topic = std.mem.sliceTo(topic, 0);
                return 0;
            }
        }.publish,
    };

    const vt = terra_transport_mqtt(&cfg);
    try std.testing.expect(vt.send_fn != null);
    try std.testing.expectEqual(@as(c_int, 0), vt.send_fn.?("otlp".ptr, 4, vt.context));
    try std.testing.expect(TestCtx.called);
    try std.testing.expectEqual(@as(u8, 1), TestCtx.qos);
    try std.testing.expectEqual(@as(u32, 4), TestCtx.len);
    try std.testing.expectEqualStrings("/terra/robot/traces", TestCtx.topic.?);
}

test "C API CoAP transport helper frames payload and increments message id" {
    const TestCtx = struct {
        var called: bool = false;
        var first_len: u32 = 0;
        var first_message_id: u16 = 0;
    };
    TestCtx.called = false;
    TestCtx.first_len = 0;
    TestCtx.first_message_id = 0;

    var cfg = CTerraCoapTransportConfig{
        .udp_send_fn = struct {
            fn send(data: [*]const u8, len: u32, _: ?*anyopaque) callconv(.c) c_int {
                TestCtx.called = true;
                TestCtx.first_len = len;
                const header = coap_transport.Header.fromBytes(data[0..4].*);
                TestCtx.first_message_id = header.message_id;
                return 0;
            }
        }.send,
        .next_message_id = 41,
    };

    const vt = terra_transport_coap(&cfg);
    try std.testing.expectEqual(@as(c_int, 0), vt.send_fn.?("otlp".ptr, 4, vt.context));
    try std.testing.expect(TestCtx.called);
    try std.testing.expect(TestCtx.first_len > 4);
    try std.testing.expectEqual(@as(u16, 41), TestCtx.first_message_id);
    try std.testing.expectEqual(@as(u16, 42), cfg.next_message_id);
}

test "C API UART transport helper frames payload with magic and CRC" {
    const TestCtx = struct {
        var called: bool = false;
        var parsed_len: usize = 0;
    };
    TestCtx.called = false;
    TestCtx.parsed_len = 0;

    var cfg = CTerraUartTransportConfig{
        .uart_write_fn = struct {
            fn write(data: [*]const u8, len: u32, _: ?*anyopaque) callconv(.c) c_int {
                TestCtx.called = true;
                const parsed = uart_transport.parseFrame(data[0..len]) orelse return -1;
                TestCtx.parsed_len = parsed.payload.len;
                return 0;
            }
        }.write,
    };

    const vt = terra_transport_uart(&cfg);
    try std.testing.expectEqual(@as(c_int, 0), vt.send_fn.?("otlp".ptr, 4, vt.context));
    try std.testing.expect(TestCtx.called);
    try std.testing.expectEqual(@as(usize, 4), TestCtx.parsed_len);
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

    var buf: [8]TestSpanRecord = undefined;
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
