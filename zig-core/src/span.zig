// Terra Zig Core — span.zig
// Span struct, StreamingScope, all span methods. NO threadlocal for context.

const std = @import("std");
const models = @import("models.zig");
const clock = @import("clock.zig");
const privacy = @import("privacy.zig");
const constants = @import("constants.zig");

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
// Mutation APIs copy string keys, values, event names, and error messages into
// span-owned storage. Callers may pass temporary C/Rust/Python/C++ buffers.
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
    string_storage: models.StringStorage = .{},

    // Events (max 8)
    events: [8]SpanEvent = undefined,
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
        _ = self.appendAttributeOwned(.{ .key = key, .value = .{ .string = value } });
    }

    pub fn setInt(self: *Span, key: []const u8, value: i64) void {
        if (self.ended) return;
        _ = self.appendAttributeOwned(.{ .key = key, .value = .{ .int_val = value } });
    }

    pub fn setDouble(self: *Span, key: []const u8, value: f64) void {
        if (self.ended) return;
        _ = self.appendAttributeOwned(.{ .key = key, .value = .{ .double_val = value } });
    }

    pub fn setBool(self: *Span, key: []const u8, value: bool) void {
        if (self.ended) return;
        _ = self.appendAttributeOwned(.{ .key = key, .value = .{ .bool_val = value } });
    }

    // ── Status ──────────────────────────────────────────────────────────
    pub fn setStatus(self: *Span, code: StatusCode, description: ?[]const u8) void {
        if (self.ended) return;
        self.status = code;
        self.status_description_len = 0;
        self.status_description_buf[0] = 0;

        const desc = description orelse return;
        if (!self.canCaptureContent()) return;

        const copy_len = @min(desc.len, self.status_description_buf.len - 1);
        if (copy_len > 0) {
            @memcpy(self.status_description_buf[0..copy_len], desc[0..copy_len]);
        }
        self.status_description_len = @intCast(copy_len);
        self.status_description_buf[copy_len] = 0;
    }

    // ── Events ──────────────────────────────────────────────────────────
    pub fn addEvent(self: *Span, name: []const u8) void {
        self.addEventTs(name, self.clock_fn(self.clock_ctx));
    }

    pub fn addEventTs(self: *Span, name: []const u8, timestamp_ns: u64) void {
        if (self.ended) return;
        if (self.event_count >= 8) return;
        const owned_name = self.string_storage.copy(name) orelse return;
        self.events[self.event_count] = .{
            .name = owned_name,
            .timestamp_ns = timestamp_ns,
            .attributes = .{},
        };
        self.event_count += 1;
    }

    pub fn addEventAttrs(self: *Span, name: []const u8, timestamp_ns: u64, attrs: []const Attribute) void {
        if (self.ended) return;
        if (self.event_count >= 8) return;
        const owned_name = self.string_storage.copy(name) orelse return;
        var event = SpanEvent{
            .name = owned_name,
            .timestamp_ns = timestamp_ns,
            .attributes = .{},
        };
        for (attrs) |attr| {
            const owned_attr = self.ownAttribute(attr) orelse return;
            _ = event.attributes.append(owned_attr);
        }
        self.events[self.event_count] = event;
        self.event_count += 1;
    }

    // ── Error ───────────────────────────────────────────────────────────
    pub fn recordError(self: *Span, error_type: []const u8, error_message: []const u8, set_status: bool) void {
        if (self.ended) return;
        const should_capture_message = self.canCaptureContent();

        var attrs_buf: [3]Attribute = undefined;
        var attr_count: usize = 0;

        attrs_buf[attr_count] = .{ .key = "exception.type", .value = .{ .string = error_type } };
        attr_count += 1;
        if (should_capture_message) {
            attrs_buf[attr_count] = .{ .key = "exception.message", .value = .{ .string = error_message } };
            attr_count += 1;
        }

        self.addEventAttrs("exception", self.clock_fn(self.clock_ctx), attrs_buf[0..attr_count]);

        if (set_status) {
            self.status = .err;
            const status_desc = if (should_capture_message) error_message else error_type;
            const len = @min(status_desc.len, self.status_description_buf.len - 1);
            @memcpy(self.status_description_buf[0..len], status_desc[0..len]);
            self.status_description_len = len;
            self.status_description_buf[len] = 0;
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
    pub fn writeRecord(self: *const Span, rec: *SpanRecord) void {
        rec.* = SpanRecord{};
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
        for (self.attributes.slice()) |attr| {
            _ = rec.appendAttributeOwned(attr);
        }
        var i: usize = 0;
        while (i < self.event_count) : (i += 1) {
            _ = rec.appendEventOwned(self.events[i]);
        }
        if (self.status_description_len > 0) {
            @memcpy(rec.status_description_buf[0..self.status_description_len], self.status_description_buf[0..self.status_description_len]);
            rec.status_description_len = self.status_description_len;
        }
    }

    fn appendAttributeOwned(self: *Span, attr: Attribute) bool {
        const owned = self.ownAttribute(attr) orelse return false;
        return self.attributes.append(owned);
    }

    fn ownAttribute(self: *Span, attr: Attribute) ?Attribute {
        const owned_key = self.string_storage.copy(attr.key) orelse return null;
        return .{
            .key = owned_key,
            .value = models.tryOwnValue(&self.string_storage, attr.value) orelse return null,
        };
    }

    fn canCaptureContent(self: *const Span) bool {
        return privacy.shouldCapture(self.content_policy_at_creation, self.include_content);
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
            self.span.setDouble(constants.keys.terra.stream_time_to_first_token_ms, ttft_ms);
        }

        // Tokens per second
        const duration_ns = now - self.span.start_time_ns;
        if (duration_ns > 0 and self.token_count > 0) {
            const duration_s = @as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0;
            const tps = @as(f64, @floatFromInt(self.token_count)) / duration_s;
            self.span.setDouble(constants.keys.terra.stream_tokens_per_second, tps);
        }

        // Output tokens
        self.span.setInt(constants.keys.terra.stream_output_tokens, @intCast(self.token_count));

        // Chunk count
        self.span.setInt(constants.keys.terra.stream_chunk_count, @intCast(self.chunk_count));

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
    while (i < 8) : (i += 1) {
        s.addEvent("evt");
    }
    try std.testing.expectEqual(@as(u8, 8), s.event_count);

    s.addEvent("overflow");
    try std.testing.expectEqual(@as(u8, 8), s.event_count);
}

test "Span setStatus with description" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.setStatus(.err, "something went wrong");
    try std.testing.expectEqual(StatusCode.err, s.status);
    try std.testing.expectEqual(@as(u8, 0), s.status_description_len);

    var capturing = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .opt_in, true);
    capturing.setStatus(.err, "something went wrong");
    try std.testing.expectEqual(StatusCode.err, capturing.status);
    try std.testing.expectEqualStrings("something went wrong", capturing.status_description_buf[0..capturing.status_description_len]);
}

test "Span setStatus clamps long descriptions and clears nil descriptions" {
    var clk = testing_clock{};
    var capturing = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .always, false);
    const long_description = [_]u8{'x'} ** 300;

    capturing.setStatus(.err, long_description[0..]);
    try std.testing.expectEqual(StatusCode.err, capturing.status);
    try std.testing.expectEqual(@as(u8, 255), capturing.status_description_len);
    try std.testing.expectEqual(@as(u8, 0), capturing.status_description_buf[255]);

    capturing.setStatus(.ok, null);
    try std.testing.expectEqual(StatusCode.ok, capturing.status);
    try std.testing.expectEqual(@as(u8, 0), capturing.status_description_len);
    try std.testing.expectEqual(@as(u8, 0), capturing.status_description_buf[0]);
}

test "Span recordError 3-param" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    s.recordError("RuntimeError", "division by zero", true);

    try std.testing.expectEqual(@as(u8, 1), s.event_count);
    try std.testing.expectEqualStrings("exception", s.events[0].name);
    try std.testing.expectEqual(@as(usize, 1), s.events[0].attributes.len);
    try std.testing.expectEqual(StatusCode.err, s.status);
    try std.testing.expectEqualStrings("RuntimeError", s.status_description_buf[0..s.status_description_len]);
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

    var rec = SpanRecord{};
    s.writeRecord(&rec);
    try std.testing.expectEqualStrings("gen_ai.inference", rec.nameSlice());
    try std.testing.expectEqual(@as(u64, 100), rec.start_time_ns);
    try std.testing.expectEqual(@as(u64, 150), rec.end_time_ns);
}

test "Span owns dynamic attribute event and error strings" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .opt_in, true);

    var key = [_]u8{ 'd', 'y', 'n', '.', 'k', 'e', 'y' };
    var value = [_]u8{ 'd', 'y', 'n', '.', 'v', 'a', 'l', 'u', 'e' };
    var event_name = [_]u8{ 'd', 'y', 'n', '.', 'e', 'v', 'e', 'n', 't' };
    var error_type = [_]u8{ 'D', 'y', 'n', 'E', 'r', 'r' };
    var error_message = [_]u8{ 'd', 'y', 'n', ' ', 'm', 's', 'g' };

    s.setString(&key, &value);
    s.addEvent(&event_name);
    s.recordError(&error_type, &error_message, true);

    @memset(&key, 'x');
    @memset(&value, 'x');
    @memset(&event_name, 'x');
    @memset(&error_type, 'x');
    @memset(&error_message, 'x');

    try std.testing.expectEqualStrings("dyn.key", s.attributes.slice()[0].key);
    try std.testing.expectEqualStrings("dyn.value", s.attributes.slice()[0].value.string);
    try std.testing.expectEqualStrings("dyn.event", s.events[0].name);
    try std.testing.expectEqualStrings("DynErr", s.events[1].attributes.slice()[0].value.string);
    try std.testing.expectEqualStrings("dyn msg", s.events[1].attributes.slice()[1].value.string);
}

test "SpanRecord owns strings after source span reset" {
    var clk = testing_clock{};
    var s = Span.init("test", TraceID.generate(), SpanID.zero, testing_clock.read, clk.context(), .never, false);
    var value = [_]u8{ 'o', 'r', 'i', 'g', 'i', 'n', 'a', 'l' };
    s.setString("dynamic.value", &value);
    s.addEvent("dynamic.event");
    var rec = SpanRecord{};
    s.writeRecord(&rec);

    @memset(&value, 'x');
    s = Span{};

    try std.testing.expectEqualStrings("dynamic.value", rec.attributes.slice()[0].key);
    try std.testing.expectEqualStrings("original", rec.attributes.slice()[0].value.string);
    try std.testing.expectEqualStrings("dynamic.event", rec.events[0].name);
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
