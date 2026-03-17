// Terra Zig Core — terra.zig
// TerraInstance: holds ALL mutable state. Lifecycle state machine.

const std = @import("std");
const config_mod = @import("config.zig");
const store_mod = @import("store.zig");
const span_mod = @import("span.zig");
const models = @import("models.zig");
const metrics_mod = @import("metrics.zig");
const clock = @import("clock.zig");
const privacy = @import("privacy.zig");
const constants = @import("constants.zig");

const TerraConfig = config_mod.TerraConfig;
const SpanStore = store_mod.SpanStore;
const Span = span_mod.Span;
const SpanRecord = models.SpanRecord;
const SpanContext = models.SpanContext;
const TraceID = models.TraceID;
const SpanID = models.SpanID;
const SpanKind = models.SpanKind;
const StatusCode = models.StatusCode;
const TerraMetrics = metrics_mod.TerraMetrics;

// ── Lifecycle State ─────────────────────────────────────────────────────
pub const LifecycleState = enum(u8) {
    stopped = 0,
    starting = 1,
    running = 2,
    shutting_down = 3,
};

// ── Error codes ─────────────────────────────────────────────────────────
pub const TerraError = enum(c_int) {
    ok = 0,
    already_initialized = 1,
    not_initialized = 2,
    invalid_config = 3,
    out_of_memory = 4,
    transport_failed = 5,
    shutting_down = 6,
};

// ── Version ─────────────────────────────────────────────────────────────
pub const TerraVersion = extern struct {
    major: u32 = 1,
    minor: u32 = 0,
    patch: u32 = 0,
};

pub const version = TerraVersion{};

// ── TerraInstance ───────────────────────────────────────────────────────
pub const TerraInstance = struct {
    config: TerraConfig,
    store: SpanStore,
    metrics: TerraMetrics = .{},
    state: LifecycleState = .stopped,
    allocator: std.mem.Allocator,
    last_error: TerraError = .ok,

    // Session
    session_id_buf: [64]u8 = [_]u8{0} ** 64,
    session_id_len: u8 = 0,

    // Service info overrides
    service_name_buf: [128]u8 = [_]u8{0} ** 128,
    service_name_len: u8 = 0,
    service_version_buf: [32]u8 = [_]u8{0} ** 32,
    service_version_len: u8 = 0,

    /// Create a new TerraInstance. Caller owns the returned pointer.
    pub fn create(allocator: std.mem.Allocator, cfg: TerraConfig) !*TerraInstance {
        if (cfg.validate()) |_| return error.InvalidConfig;

        const store = try SpanStore.init(allocator, cfg.max_spans);

        const inst = try allocator.create(TerraInstance);
        inst.* = .{
            .config = cfg,
            .store = store,
            .allocator = allocator,
            .state = .running,
        };

        // Copy service name/version from config
        const sn = std.mem.sliceTo(cfg.service_name, 0);
        const copy_sn = @min(sn.len, @as(usize, 128));
        @memcpy(inst.service_name_buf[0..copy_sn], sn[0..copy_sn]);
        inst.service_name_len = @intCast(copy_sn);

        const sv = std.mem.sliceTo(cfg.service_version, 0);
        const copy_sv = @min(sv.len, @as(usize, 32));
        @memcpy(inst.service_version_buf[0..copy_sv], sv[0..copy_sv]);
        inst.service_version_len = @intCast(copy_sv);

        return inst;
    }

    /// Destroy this instance and free all resources.
    pub fn destroy(self: *TerraInstance) void {
        self.state = .shutting_down;
        self.config.transport_vtable.flush();
        self.config.transport_vtable.shutdown();
        self.store.deinit();
        self.state = .stopped;
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    // ── Span creation ───────────────────────────────────────────────────
    pub fn beginSpan(
        self: *TerraInstance,
        name: []const u8,
        kind: SpanKind,
        parent_ctx: ?SpanContext,
        include_content: bool,
    ) ?*Span {
        if (self.state != .running) return null;

        const s = self.store.allocateSpan() orelse {
            self.metrics.spans_dropped.increment();
            return null;
        };

        const trace_id = if (parent_ctx) |ctx| ctx.traceID() else TraceID.generate();
        const parent_id = if (parent_ctx) |ctx| ctx.spanID() else SpanID.zero;

        s.* = Span.init(
            name,
            trace_id,
            parent_id,
            self.config.clock_fn,
            self.config.clock_ctx,
            self.config.content_policy,
            include_content,
        );
        s.kind = kind;

        self.metrics.spans_created.increment();
        return s;
    }

    pub fn beginInferenceSpan(self: *TerraInstance, parent_ctx: ?SpanContext, model: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.inference, .client, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "inference");
        if (model) |m| s.setString(constants.keys.gen_ai.request_model, m);
        return s;
    }

    pub fn beginEmbeddingSpan(self: *TerraInstance, parent_ctx: ?SpanContext, model: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.embedding, .client, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "embeddings");
        if (model) |m| s.setString(constants.keys.gen_ai.request_model, m);
        return s;
    }

    pub fn beginAgentSpan(self: *TerraInstance, parent_ctx: ?SpanContext, agent_name: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.agent_invocation, .internal, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "invoke_agent");
        if (agent_name) |n| s.setString(constants.keys.gen_ai.agent_name, n);
        return s;
    }

    pub fn beginToolSpan(self: *TerraInstance, parent_ctx: ?SpanContext, tool_name: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.tool_execution, .internal, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "execute_tool");
        if (tool_name) |n| s.setString(constants.keys.gen_ai.tool_name, n);
        return s;
    }

    pub fn beginSafetySpan(self: *TerraInstance, parent_ctx: ?SpanContext, check_name: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.safety_check, .internal, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "safety_check");
        if (check_name) |n| s.setString(constants.keys.terra.safety_check_name, n);
        return s;
    }

    pub fn beginStreamingSpan(self: *TerraInstance, parent_ctx: ?SpanContext, model: ?[]const u8, include_content: bool) ?*Span {
        const s = self.beginSpan(constants.span_names.inference, .client, parent_ctx, include_content) orelse return null;
        s.setString(constants.keys.gen_ai.operation_name, "inference");
        s.setBool(constants.keys.gen_ai.request_stream, true);
        if (model) |m| s.setString(constants.keys.gen_ai.request_model, m);
        return s;
    }

    // ── Span context extraction ─────────────────────────────────────────
    pub fn spanContext(s: *const Span) SpanContext {
        return SpanContext.fromIDs(s.trace_id, s.span_id);
    }

    // ── End span ────────────────────────────────────────────────────────
    pub fn endSpan(self: *TerraInstance, s: *Span) void {
        s.end();
        self.store.completeSpan(s);
    }

    // ── Session ─────────────────────────────────────────────────────────
    pub fn setSessionId(self: *TerraInstance, sid: []const u8) void {
        const copy_len = @min(sid.len, @as(usize, 64));
        @memcpy(self.session_id_buf[0..copy_len], sid[0..copy_len]);
        self.session_id_len = @intCast(copy_len);
    }

    pub fn sessionId(self: *const TerraInstance) ?[]const u8 {
        if (self.session_id_len == 0) return null;
        return self.session_id_buf[0..self.session_id_len];
    }

    // ── Service info ────────────────────────────────────────────────────
    pub fn setServiceInfo(self: *TerraInstance, name: []const u8, ver: []const u8) void {
        const copy_n = @min(name.len, @as(usize, 128));
        @memcpy(self.service_name_buf[0..copy_n], name[0..copy_n]);
        self.service_name_len = @intCast(copy_n);

        const copy_v = @min(ver.len, @as(usize, 32));
        @memcpy(self.service_version_buf[0..copy_v], ver[0..copy_v]);
        self.service_version_len = @intCast(copy_v);
    }

    // ── Diagnostics ─────────────────────────────────────────────────────
    pub fn spansDropped(self: *const TerraInstance) u64 {
        return @intCast(self.metrics.spans_dropped.get());
    }

    pub fn isRunning(self: *const TerraInstance) bool {
        return self.state == .running;
    }

    // ── Test support ────────────────────────────────────────────────────
    pub fn drainSpans(self: *TerraInstance, buf: []SpanRecord) u32 {
        return self.store.drainCompleted(buf, @intCast(buf.len));
    }

    pub fn reset(self: *TerraInstance) void {
        self.store.reset();
        self.metrics.reset();
        self.session_id_len = 0;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "TerraInstance create and destroy" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    try std.testing.expect(inst.isRunning());
    inst.destroy();
}

test "TerraInstance full lifecycle" {
    var clk = clock.TestingClock{ .current_ns = 1_000_000 };
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    cfg.clock_fn = clock.TestingClock.read;
    cfg.clock_ctx = clk.context();

    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    // Create inference span
    const s = inst.beginInferenceSpan(null, "gpt-4", false);
    try std.testing.expect(s != null);

    clk.advance(5_000_000);
    inst.endSpan(s.?);

    // Drain
    var buf: [4]SpanRecord = undefined;
    const count = inst.drainSpans(&buf);
    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqualStrings("gen_ai.inference", buf[0].nameSlice());
}

test "TerraInstance all 6 span types" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    const spans = [_]?*Span{
        inst.beginInferenceSpan(null, "model", false),
        inst.beginEmbeddingSpan(null, "embed", false),
        inst.beginAgentSpan(null, "agent-1", false),
        inst.beginToolSpan(null, "search", false),
        inst.beginSafetySpan(null, "toxicity", false),
        inst.beginStreamingSpan(null, "stream-model", false),
    };

    for (&spans) |maybe_span| {
        try std.testing.expect(maybe_span != null);
        inst.endSpan(maybe_span.?);
    }

    var buf: [8]SpanRecord = undefined;
    const count = inst.drainSpans(&buf);
    try std.testing.expectEqual(@as(u32, 6), count);
}

test "TerraInstance context propagation" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    // Parent span
    const parent = inst.beginInferenceSpan(null, "parent-model", false).?;
    const parent_ctx = TerraInstance.spanContext(parent);

    // Child span with parent context
    const child = inst.beginToolSpan(parent_ctx, "child-tool", false).?;

    // Child should inherit trace_id from parent
    try std.testing.expect(child.trace_id.eql(parent.trace_id));
    try std.testing.expect(child.parent_span_id.eql(parent.span_id));

    inst.endSpan(child);
    inst.endSpan(parent);
}

test "TerraInstance session management" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    try std.testing.expectEqual(@as(?[]const u8, null), inst.sessionId());

    inst.setSessionId("session-abc-123");
    try std.testing.expectEqualStrings("session-abc-123", inst.sessionId().?);
}

test "TerraInstance reset" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    const s = inst.beginInferenceSpan(null, null, false).?;
    inst.endSpan(s);
    inst.setSessionId("test");

    inst.reset();

    var buf: [4]SpanRecord = undefined;
    try std.testing.expectEqual(@as(u32, 0), inst.drainSpans(&buf));
    try std.testing.expectEqual(@as(?[]const u8, null), inst.sessionId());
}

test "TerraInstance spans_dropped when full" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    cfg.max_spans = 2;
    cfg.batch_size = 2;
    const inst = try TerraInstance.create(std.testing.allocator, cfg);
    defer inst.destroy();

    // Fill both slots with active (not ended) spans
    const s1 = inst.beginInferenceSpan(null, null, false);
    const s2 = inst.beginInferenceSpan(null, null, false);
    try std.testing.expect(s1 != null);
    try std.testing.expect(s2 != null);

    // Third should be dropped (no completed spans to evict)
    const s3 = inst.beginInferenceSpan(null, null, false);
    try std.testing.expect(s3 == null);
    try std.testing.expectEqual(@as(u64, 1), inst.spansDropped());
}

test "TerraInstance invalid config rejected" {
    var cfg = TerraConfig.default();
    cfg.allocator = std.testing.allocator;
    cfg.max_spans = 0;
    const result = TerraInstance.create(std.testing.allocator, cfg);
    try std.testing.expectError(error.InvalidConfig, result);
}
