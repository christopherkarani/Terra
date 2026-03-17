// Terra Zig Core — models.zig
// Core data types: TraceID, SpanID, SpanContext, AttributeValue, SpanRecord, etc.

const std = @import("std");
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");

pub const MAX_SPAN_NAME = build_options.TERRA_MAX_SPAN_NAME;

// ── TraceID ─────────────────────────────────────────────────────────────
pub const TraceID = struct {
    hi: u64,
    lo: u64,

    pub const zero = TraceID{ .hi = 0, .lo = 0 };

    pub fn generate() TraceID {
        var buf: [16]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return .{
            .hi = std.mem.readInt(u64, buf[0..8], .big),
            .lo = std.mem.readInt(u64, buf[8..16], .big),
        };
    }

    pub fn isZero(self: TraceID) bool {
        return self.hi == 0 and self.lo == 0;
    }

    pub fn eql(a: TraceID, b: TraceID) bool {
        return a.hi == b.hi and a.lo == b.lo;
    }

    pub fn toBytes(self: TraceID) [16]u8 {
        var buf: [16]u8 = undefined;
        std.mem.writeInt(u64, buf[0..8], self.hi, .big);
        std.mem.writeInt(u64, buf[8..16], self.lo, .big);
        return buf;
    }
};

// ── SpanID ──────────────────────────────────────────────────────────────
pub const SpanID = struct {
    id: u64,

    pub const zero = SpanID{ .id = 0 };

    pub fn generate() SpanID {
        var buf: [8]u8 = undefined;
        std.crypto.random.bytes(&buf);
        return .{
            .id = std.mem.readInt(u64, buf[0..8], .big),
        };
    }

    pub fn isZero(self: SpanID) bool {
        return self.id == 0;
    }

    pub fn eql(a: SpanID, b: SpanID) bool {
        return a.id == b.id;
    }

    pub fn toBytes(self: SpanID) [8]u8 {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, buf[0..8], self.id, .big);
        return buf;
    }
};

// ── SpanContext ──────────────────────────────────────────────────────────
// Flat value type matching C ABI terra_span_context_t
pub const SpanContext = extern struct {
    trace_id_hi: u64 = 0,
    trace_id_lo: u64 = 0,
    span_id: u64 = 0,

    pub const invalid = SpanContext{};

    pub fn isValid(self: SpanContext) bool {
        return !(self.trace_id_hi == 0 and self.trace_id_lo == 0 and self.span_id == 0);
    }

    pub fn fromIDs(trace_id: TraceID, span_id: SpanID) SpanContext {
        return .{
            .trace_id_hi = trace_id.hi,
            .trace_id_lo = trace_id.lo,
            .span_id = span_id.id,
        };
    }

    pub fn traceID(self: SpanContext) TraceID {
        return .{ .hi = self.trace_id_hi, .lo = self.trace_id_lo };
    }

    pub fn spanID(self: SpanContext) SpanID {
        return .{ .id = self.span_id };
    }
};

// ── SpanKind ────────────────────────────────────────────────────────────
pub const SpanKind = enum(u8) {
    internal = 0,
    server = 1,
    client = 2,
    producer = 3,
    consumer = 4,
};

// ── StatusCode ──────────────────────────────────────────────────────────
pub const StatusCode = enum(u8) {
    unset = 0,
    ok = 1,
    err = 2,
};

// ── AttributeValue ──────────────────────────────────────────────────────
pub const AttributeValue = union(enum) {
    string: []const u8,
    bool_val: bool,
    int_val: i64,
    double_val: f64,
    bytes: []const u8,
    null_val: void,

    pub fn eql(a: AttributeValue, b: AttributeValue) bool {
        const tag_a = std.meta.activeTag(a);
        const tag_b = std.meta.activeTag(b);
        if (tag_a != tag_b) return false;

        return switch (a) {
            .string => |s| std.mem.eql(u8, s, b.string),
            .bool_val => |v| v == b.bool_val,
            .int_val => |v| v == b.int_val,
            .double_val => |v| v == b.double_val,
            .bytes => |s| std.mem.eql(u8, s, b.bytes),
            .null_val => true,
        };
    }
};

// ── Attribute ───────────────────────────────────────────────────────────
pub const Attribute = struct {
    key: []const u8,
    value: AttributeValue,
};

// ── SpanEvent ───────────────────────────────────────────────────────────
pub const SpanEvent = struct {
    name: []const u8,
    timestamp_ns: u64,
    attributes: BoundedAttributes(4),
};

// ── BoundedAttributes ───────────────────────────────────────────────────
pub fn BoundedAttributes(comptime max: usize) type {
    return struct {
        items: [max]Attribute = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn append(self: *Self, attr: Attribute) bool {
            if (self.len >= max) return false;
            self.items[self.len] = attr;
            self.len += 1;
            return true;
        }

        pub fn slice(self: *const Self) []const Attribute {
            return self.items[0..self.len];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }
    };
}

// ── SpanRecord ──────────────────────────────────────────────────────────
// Complete span data struct for serialization/export (all fields flattened)
pub const SpanRecord = struct {
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
    include_content: bool = false,
    content_policy_at_creation: u8 = 0, // ContentPolicy enum value

    // Flattened attributes (max 64)
    attributes: BoundedAttributes(64) = .{},

    // Flattened events (max 8)
    events: [8]SpanEvent = undefined,
    event_count: u8 = 0,

    pub fn nameSlice(self: *const SpanRecord) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn setName(self: *SpanRecord, n: []const u8) void {
        const copy_len = @min(n.len, MAX_SPAN_NAME);
        @memcpy(self.name[0..copy_len], n[0..copy_len]);
        self.name_len = @intCast(copy_len);
    }

    pub fn statusDescriptionSlice(self: *const SpanRecord) ?[]const u8 {
        if (self.status_description_len == 0) return null;
        return self.status_description_buf[0..self.status_description_len];
    }

    pub fn durationNs(self: *const SpanRecord) u64 {
        if (self.end_time_ns > self.start_time_ns) {
            return self.end_time_ns - self.start_time_ns;
        }
        return 0;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "TraceID.generate produces unique non-zero IDs" {
    const id1 = TraceID.generate();
    const id2 = TraceID.generate();
    try std.testing.expect(!id1.isZero());
    try std.testing.expect(!id2.isZero());
    try std.testing.expect(!id1.eql(id2));
}

test "TraceID.zero is zero" {
    try std.testing.expect(TraceID.zero.isZero());
}

test "TraceID.toBytes round-trip" {
    const id = TraceID{ .hi = 0x0102030405060708, .lo = 0x090A0B0C0D0E0F10 };
    const bytes = id.toBytes();
    try std.testing.expectEqual(@as(u8, 0x01), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x10), bytes[15]);
}

test "SpanID.generate produces unique non-zero IDs" {
    const id1 = SpanID.generate();
    const id2 = SpanID.generate();
    try std.testing.expect(!id1.isZero());
    try std.testing.expect(!id2.isZero());
    try std.testing.expect(!id1.eql(id2));
}

test "SpanContext flat layout and isValid" {
    const ctx = SpanContext.invalid;
    try std.testing.expect(!ctx.isValid());

    const valid = SpanContext.fromIDs(
        TraceID{ .hi = 1, .lo = 2 },
        SpanID{ .id = 3 },
    );
    try std.testing.expect(valid.isValid());
    try std.testing.expectEqual(@as(u64, 1), valid.trace_id_hi);
    try std.testing.expectEqual(@as(u64, 2), valid.trace_id_lo);
    try std.testing.expectEqual(@as(u64, 3), valid.span_id);
}

test "SpanContext roundtrip via traceID/spanID" {
    const tid = TraceID{ .hi = 42, .lo = 99 };
    const sid = SpanID{ .id = 7 };
    const ctx = SpanContext.fromIDs(tid, sid);
    try std.testing.expect(ctx.traceID().eql(tid));
    try std.testing.expect(ctx.spanID().eql(sid));
}

test "AttributeValue.eql" {
    const str1 = AttributeValue{ .string = "hello" };
    const str2 = AttributeValue{ .string = "hello" };
    const str3 = AttributeValue{ .string = "world" };
    try std.testing.expect(str1.eql(str2));
    try std.testing.expect(!str1.eql(str3));

    const int1 = AttributeValue{ .int_val = 42 };
    const int2 = AttributeValue{ .int_val = 42 };
    try std.testing.expect(int1.eql(int2));
    try std.testing.expect(!int1.eql(str1));

    const null1 = AttributeValue{ .null_val = {} };
    const null2 = AttributeValue{ .null_val = {} };
    try std.testing.expect(null1.eql(null2));
}

test "BoundedAttributes append and bounds" {
    var attrs = BoundedAttributes(2){};
    try std.testing.expect(attrs.append(.{ .key = "k1", .value = .{ .int_val = 1 } }));
    try std.testing.expect(attrs.append(.{ .key = "k2", .value = .{ .int_val = 2 } }));
    try std.testing.expect(!attrs.append(.{ .key = "k3", .value = .{ .int_val = 3 } })); // Full
    try std.testing.expectEqual(@as(usize, 2), attrs.slice().len);
}

test "SpanRecord setName and nameSlice" {
    var rec = SpanRecord{};
    rec.setName("gen_ai.inference");
    try std.testing.expectEqualStrings("gen_ai.inference", rec.nameSlice());
}

test "SpanRecord setName truncation" {
    var rec = SpanRecord{};
    const long_name = "a" ** (MAX_SPAN_NAME + 50);
    rec.setName(long_name);
    try std.testing.expectEqual(@as(u8, MAX_SPAN_NAME), rec.name_len);
}

test "SpanRecord durationNs" {
    var rec = SpanRecord{};
    rec.start_time_ns = 1000;
    rec.end_time_ns = 5000;
    try std.testing.expectEqual(@as(u64, 4000), rec.durationNs());
}

test "SpanKind and StatusCode enum values match OTel" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(SpanKind.internal));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(SpanKind.client));
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(StatusCode.unset));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(StatusCode.ok));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(StatusCode.err));
}
