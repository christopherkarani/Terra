// Terra Zig Core — span.zig
// Span struct, StreamingScope, all span methods. NO threadlocal for context.

const std = @import("std");
const models = @import("models.zig");
const clock = @import("clock.zig");
const privacy = @import("privacy.zig");

const TraceID = models.TraceID;
const SpanID = models.SpanID;
const SpanKind = models.SpanKind;
const StatusCode = models.StatusCode;
const Attribute = models.Attribute;
const AttributeValue = models.AttributeValue;
const SpanEvent = models.SpanEvent;
const BoundedAttributes = models.BoundedAttributes;
const SpanRecord = models.SpanRecord;
const MAX_SPAN_NAME = models.MAX_SPAN_NAME;

// ── Span ────────────────────────────────────────────────────────────────
// NOTE: String ownership contract
// Attribute keys, string values, event names, and error messages are stored
// by reference ([]const u8 slices). Callers MUST ensure these strings remain
// valid for the lifetime of the span (until after end() and drain/export).
// For C callers: string parameters passed to terra_span_set_string() etc.
// must remain valid until terra_span_end() returns. Static string literals
// are always safe. Stack-allocated buffers are safe only if the span is
// ended before the buffer goes out of scope.
pub const Span = struct {
    trace_id: TraceID = TraceID.zero,
    span_id: SpanID = SpanID.zero,
    parent_span_id: SpanID = SpanID.zero,
    name: [MAX_SPAN_NAME]u8 = [_]u8{0} ** MAX_SPAN_NAME,
    name_len: u8 = 0,
    kind: SpanKind = .internal,
    status: StatusCode = .unset,
    status_description_buf: [256]u8 = [_]u8{0} ** 256,
    status_description_len: u8 = 0,
    start_time_ns: u64 = 0,
    end_time_ns: u64 = 0,
    ended: bool = false,
    active: bool = false,

    // Privacy
    include_content: bool = false,
    content_policy_at_creation: privacy.ContentPolicy = .never,

    // Attributes (max 64)
    attributes: BoundedAttributes(64) = .{},

    // Events (max 32)
    events: [32]SpanEvent = undefined,
    event_count: u8 = 0,

    // Clock reference
    clock_fn: clock.ClockFn = clock.stdClock,
    clock_ctx: ?*anyopaque = null,

    // ── Initialization ──────────────────────────────────────────────────
    pub fn init(
        name: []const u8,
        trace_id: TraceID,
        parent_span_id: SpanID,
        clk_fn: clock.ClockFn,
        clk_ctx: ?*anyopaque,
        policy: privacy.ContentPolicy,
        incl_content: bool,
    ) Span {
        var s = Span{};
        s.setName(name);
        s.trace_id = trace_id;
        s.span_id = SpanID.generate();
        s.parent_span_id = parent_span_id;
        s.clock_fn = clk_fn;
        s.clock_ctx = clk_ctx;
        s.start_time_ns = clk_fn(clk_ctx);
        s.active = true;
        s.content_policy_at_creation = policy;
        s.include_content = incl_content;
        return s;
    }

    // ── Name ────────────────────────────────────────────────────────────
    pub fn setName(self: *Span, n: []const u8) void {
        const copy_len = @min(n.len, MAX_SPAN_NAME);
        @memcpy(self.name[0..copy_len], n[0..copy_len]);
        self.name_len = @intCast(copy_len);
    }

    pub fn nameSlice(self: *const Span) []const u8 {
        return self.name[0..self.name_len];
    }

    // ── Attributes ──────────────────────────────────────────────────────
    pub fn setString(self: *Span, key: []const u8, value: []const u8) void {
        if (self.ended) return;
        _ = self.attributes.append(.{ .key = key, .value = .{ .string = value } });
    }

    pub fn setInt(self: *Span, key: []const u8, value: i64) void {
        if (self.ended) return;
        _ = self.attributes.append(.{ .key = key, .value = .{ .int_val = value } });
    }

    pub fn setDouble(self: *Span, key: []const u8, value: f64) void {
        if (self.ended) return;
        _ = self.attributes.append(.{ .key = key, .value = .{ .double_val = value } });
    }

    pub fn setBool(self: *Span, key: []const u8, value: bool) void {
        if (self.ended) return;
        _ = self.attributes.append(.{ .key = key, .value = .{ .bool_val = value } });
    }

    // ── Status ──────────────────────────────────────────────────────────
    pub fn setStatus(self: *Span, code: StatusCode, description: ?[]const u8) void {
        if (self.ended) return;
        self.status = code;
        if (description) |desc| {
            const copy_len = @min(desc.len, @as(usize, 256));
            @memcpy(self.status_description_buf[0..copy_len], desc[0..copy_len]);
            self.status_description_len = @intCast(copy_len);
        }
    }

    // ── Events ──────────────────────────────────────────────────────────
    pub fn addEvent(self: *Span, name: []const u8) void {
        self.addEventTs(name, self.clock_fn(self.clock_ctx));
    }

    pub fn addEventTs(self: *Span, name: []const u8, timestamp_ns: u64) void {
        if (self.ended) return;
        if (self.event_count >= 32) return;
        self.events[self.event_count] = .{
            .name = name,
            .timestamp_ns = timestamp_ns,
            .attributes = .{},
        };
        self.event_count += 1;
    }

    pub fn addEventAttrs(self: *Span, name: []const u8, timestamp_ns: u64, attrs: []const Attribute) void {
        if (self.ended) return;
        if (self.event_count >= 32) return;
        var event = SpanEvent{
            .name = name,
            .timestamp_ns = timestamp_ns,
            .attributes = .{},
        };
        for (attrs) |attr| {
            _ = event.attributes.append(attr);
        }
        self.events[self.event_count] = event;
        self.event_count += 1;
    }

    // ── Error ───────────────────────────────────────────────────────────
    pub fn recordError(self: *Span, error_type: []const u8, error_message: []const u8, set_status: bool) void {
        if (self.ended) return;

        var attrs_buf: [3]Attribute = undefined;
        var attr_count: usize = 0;

        attrs_buf[attr_count] = .{ .key = "exception.type", .value = .{ .string = error_type } };
        attr_count += 1;
        attrs_buf[attr_count] = .{ .key = "exception.message", .value = .{ .string = error_message } };
        attr_count += 1;

        self.addEventAttrs("exception", self.clock_fn(self.clock_ctx), attrs_buf[0..attr_count]);

        if (set_status) {
            self.setStatus(.err, error_message);
        }
    }

    // ── End ─────────────────────────────────────────────────────────────
    pub fn end(self: *Span) void {
        if (self.ended) return; // Idempotent
        self.ended = true;
        self.active = false;
        self.end_time_ns = self.clock_fn(self.clock_ctx);
    }

    // ── Export to SpanRecord ────────────────────────────────────────────
    pub fn toRecord(self: *const Span) SpanRecord {
        var rec = SpanRecord{};
        rec.trace_id = self.trace_id;
        rec.span_id = self.span_id;
        rec.parent_span_id = self.parent_span_id;
        rec.name = self.name;
        rec.name_len = self.name_len;
        rec.kind = self.kind;
        rec.status = self.status;
        rec.start_time_ns = self.start_time_ns;
        rec.end_time_ns = self.end_time_ns;
        rec.include_content = self.include_content;
        rec.content_policy_at_creation = @intFromEnum(self.content_policy_at_creation);
        rec.attributes = self.attributes;
        rec.event_count = self.event_count;
        if (self.event_count > 0) {
            @memcpy(rec.events[0..self.event_count], self.events[0..self.event_count]);
        }
        if (self.status_description_len > 0) {
            @memcpy(rec.status_description_buf[0..self.status_description_len], self.status_description_buf[0..self.status_description_len]);
            rec.status_description_len = self.status_description_len;
        }
        return rec;
    }
};

// ── StreamingScope ──────────────────────────────────────────────────────
pub const StreamingScope = struct {
    span: *Span,
    first_token_time_ns: ?u64 = null,
    token_count: u32 = 0,
    chunk_count: u32 = 0,
    last_chunk_time_ns: u64 = 0,
    has_stall: bool = false,
    stall_threshold_ns: u64 = 300_000_000, // 300ms

    pub fn init(s: *Span) StreamingScope {
        return .{
            .span = s,
            .last_chunk_time_ns = s.start_time_ns,
        };
    }

    pub fn recordFirstToken(self: *StreamingScope) void {
        if (self.first_token_time_ns != null) return; // Already recorded
        self.first_token_time_ns = self.span.clock_fn(self.span.clock_ctx);
        self.token_count += 1;
        self.chunk_count += 1;
        self.last_chunk_time_ns = self.first_token_time_ns.?;
    }

    pub fn recordToken(self: *StreamingScope) void {
        self.token_count += 1;
    }

    pub fn recordChunk(self: *StreamingScope) void {
        const now = self.span.clock_fn(self.span.clock_ctx);
        if (now - self.last_chunk_time_ns > self.stall_threshold_ns) {
            self.has_stall = true;
        }
        self.last_chunk_time_ns = now;
        self.chunk_count += 1;
    }

    pub fn finish(self: *StreamingScope) void {
        const now = self.span.clock_fn(self.span.clock_ctx);

        // TTFT
        if (self.first_token_time_ns) |ttft_ns| {
            const ttft_ms = @as(f64, @floatFromInt(ttft_ns - self.span.start_time_ns)) / 1_000_000.0;
            self.span.setDouble("terra.stream.time_to_first_token_ms", ttft_ms);
        }

        // Tokens per second
        const duration_ns = now - self.span.start_time_ns;
        if (duration_ns > 0 and self.token_count > 0) {
            const duration_s = @as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0;
            const tps = @as(f64, @floatFromInt(self.token_count)) / duration_s;
            self.span.setDouble("terra.stream.tokens_per_second", tps);
        }

        // Output tokens
        self.span.setInt("terra.stream.output_tokens", @intCast(self.token_count));

        // Chunk count
        self.span.setInt("terra.stream.chunk_count", @intCast(self.chunk_count));

        // Note: does NOT call span.end() — caller ends span separately
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
const testing_clock = @import("clock.zig").TestingClock;

test "Span lifecycle: create, set attrs, end" {
    var clk = testing_clock{ .current_ns = 1_000_000 };

    var s = Span.init(
        "gen_ai.inference",
        TraceID{ .hi = 1, .lo = 2 },
        SpanID.zero,
        testing_clock.read,
        clk.context(),
        .never,
        false,
    );

    try std.testing.expectEqualStrings("gen_ai.inference", s.nameSlice());
    try std.testing.expect(s.active);
    try std.testing.expect(!s.ended);
    try std.testing.expectEqual(@as(u64, 1_000_000), s.start_time_ns);

    s.setString("gen_ai.request.model", "gpt-4");
    s.setInt("gen_ai.request.max_tokens", 1024);
    try std.testing.expectEqual(@as(usize, 2), s.attributes.len);

    clk.advance(5_000_000); // 5ms later
    s.end();

    try std.testing.expect(s.ended);
    try std.testing.expect(!s.active);
    try std.testing.expectEqual(@as(u64, 6_000_000), s.end_time_ns);
}

test "Span end is idempotent" {
    var clk = testing_clock{ .current_ns = 1000 };
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);

    clk.advance(100);
    s.end();
    const end1 = s.end_time_ns;

    clk.advance(200);
    s.end(); // Should be no-op
    try std.testing.expectEqual(end1, s.end_time_ns);
}

test "Span setters no-op after end" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.end();

    s.setString("key", "value");
    try std.testing.expectEqual(@as(usize, 0), s.attributes.len);

    s.addEvent("event");
    try std.testing.expectEqual(@as(u8, 0), s.event_count);
}

test "Span attribute bounds" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);

    var i: usize = 0;
    while (i < 64) : (i += 1) {
        s.setInt("key", @intCast(i));
    }
    try std.testing.expectEqual(@as(usize, 64), s.attributes.len);

    // 65th should be silently dropped
    s.setInt("overflow", 999);
    try std.testing.expectEqual(@as(usize, 64), s.attributes.len);
}

test "Span event bounds" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);

    var i: u8 = 0;
    while (i < 32) : (i += 1) {
        s.addEvent("evt");
    }
    try std.testing.expectEqual(@as(u8, 32), s.event_count);

    s.addEvent("overflow");
    try std.testing.expectEqual(@as(u8, 32), s.event_count);
}

test "Span setStatus with description" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.setStatus(.err, "something went wrong");
    try std.testing.expectEqual(StatusCode.err, s.status);
    try std.testing.expectEqualStrings("something went wrong", s.status_description_buf[0..s.status_description_len]);
}

test "Span recordError 3-param" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.recordError("RuntimeError", "division by zero", true);

    try std.testing.expectEqual(@as(u8, 1), s.event_count);
    try std.testing.expectEqualStrings("exception", s.events[0].name);
    try std.testing.expectEqual(StatusCode.err, s.status);
}

test "Span recordError without set_status" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.recordError("Warning", "something odd", false);

    try std.testing.expectEqual(@as(u8, 1), s.event_count);
    try std.testing.expectEqual(StatusCode.unset, s.status);
}

test "Span toRecord" {
    var clk = testing_clock{ .current_ns = 100 };
    var s = Span.init("gen_ai.inference", TraceID{ .hi = 10, .lo = 20 }, SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.setString("model", "test-model");
    clk.advance(50);
    s.end();

    const rec = s.toRecord();
    try std.testing.expectEqualStrings("gen_ai.inference", rec.nameSlice());
    try std.testing.expectEqual(@as(u64, 100), rec.start_time_ns);
    try std.testing.expectEqual(@as(u64, 150), rec.end_time_ns);
}

test "StreamingScope TTFT calculation" {
    var clk = testing_clock{ .current_ns = 1_000_000_000 }; // 1s
    var s = Span.init("gen_ai.inference", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);

    var scope = StreamingScope.init(&s);

    clk.advance(200_000_000); // 200ms later
    scope.recordFirstToken();
    try std.testing.expectEqual(@as(?u64, 1_200_000_000), scope.first_token_time_ns);
    try std.testing.expectEqual(@as(u32, 1), scope.token_count);

    scope.recordToken();
    scope.recordToken();
    try std.testing.expectEqual(@as(u32, 3), scope.token_count);

    clk.advance(100_000_000); // another 100ms
    scope.finish();

    // Check TTFT was set on span
    var found_ttft = false;
    for (s.attributes.slice()) |attr| {
        if (std.mem.eql(u8, attr.key, "terra.stream.time_to_first_token_ms")) {
            found_ttft = true;
            try std.testing.expectApproxEqAbs(@as(f64, 200.0), attr.value.double_val, 0.1);
        }
    }
    try std.testing.expect(found_ttft);
}

test "StreamingScope stall detection (300ms)" {
    var clk = testing_clock{ .current_ns = 0 };
    var s = Span.init("stream", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);

    var scope = StreamingScope.init(&s);
    scope.recordFirstToken();

    // No stall yet
    clk.advance(100_000_000); // 100ms
    scope.recordChunk();
    try std.testing.expect(!scope.has_stall);

    // Stall: 301ms gap
    clk.advance(301_000_000);
    scope.recordChunk();
    try std.testing.expect(scope.has_stall);
}

test "StreamingScope finish does not end span" {
    var clk = testing_clock{};
    var s = Span.init("stream", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    var scope = StreamingScope.init(&s);
    scope.finish();
    try std.testing.expect(!s.ended); // Span still open
}
