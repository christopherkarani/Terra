// Terra Zig Core — otlp.zig
// Hand-rolled protobuf wire format serializer for OTLP v0.20.
// Pure serialization — no I/O, no allocations beyond output buffer.

const std = @import("std");
const models = @import("models.zig");
const resource_mod = @import("resource.zig");

const SpanRecord = models.SpanRecord;
const Attribute = models.Attribute;
const AttributeValue = models.AttributeValue;
const SpanEvent = models.SpanEvent;

// ── Protobuf wire format constants ──────────────────────────────────────
// Wire types
const VARINT: u3 = 0;
const I64: u3 = 1;
const LEN: u3 = 2;
const I32: u3 = 5;

// OTLP field numbers
const field = struct {
    // ExportTraceServiceRequest
    const resource_spans = 1;
    // ResourceSpans
    const resource = 1;
    const scope_spans = 2;
    // Resource
    const resource_attributes = 1;
    // ScopeSpans
    const scope = 1;
    const scope_spans_spans = 2;
    // InstrumentationScope
    const scope_name = 1;
    const scope_version = 2;
    // Span
    const span_trace_id = 1;
    const span_span_id = 2;
    const span_trace_state = 3;
    const span_parent_span_id = 4;
    const span_name = 5;
    const span_kind = 6;
    const span_start_time = 7;
    const span_end_time = 8;
    const span_attributes = 9;
    const span_events = 10;
    const span_links = 11;
    const span_status = 15;
    // Event
    const event_time = 1;
    const event_name = 2;
    const event_attributes = 3;
    // Status
    const status_message = 1;
    const status_code = 2;
    // KeyValue
    const kv_key = 1;
    const kv_value = 2;
    // AnyValue
    const av_string = 1;
    const av_bool = 2;
    const av_int = 3;
    const av_double = 4;
    const av_bytes = 7;
};

// ── Wire format helpers ─────────────────────────────────────────────────
const ProtoWriter = struct {
    buf: []u8,
    pos: usize = 0,

    fn remaining(self: *const ProtoWriter) usize {
        return self.buf.len - self.pos;
    }

    fn writeVarint(self: *ProtoWriter, value: u64) bool {
        var v = value;
        while (true) {
            if (self.pos >= self.buf.len) return false;
            if (v < 0x80) {
                self.buf[self.pos] = @intCast(v);
                self.pos += 1;
                return true;
            }
            self.buf[self.pos] = @intCast((v & 0x7F) | 0x80);
            self.pos += 1;
            v >>= 7;
        }
    }

    fn writeSignedVarint(self: *ProtoWriter, value: i64) bool {
        return self.writeVarint(@bitCast(value));
    }

    fn writeTag(self: *ProtoWriter, field_number: u32, wire_type: u3) bool {
        return self.writeVarint((@as(u64, field_number) << 3) | wire_type);
    }

    fn writeBytes(self: *ProtoWriter, data: []const u8) bool {
        if (self.pos + data.len > self.buf.len) return false;
        @memcpy(self.buf[self.pos..][0..data.len], data);
        self.pos += data.len;
        return true;
    }

    fn writeLenDelimited(self: *ProtoWriter, field_number: u32, data: []const u8) bool {
        if (!self.writeTag(field_number, LEN)) return false;
        if (!self.writeVarint(data.len)) return false;
        return self.writeBytes(data);
    }

    fn writeFixed64(self: *ProtoWriter, field_number: u32, value: u64) bool {
        if (!self.writeTag(field_number, I64)) return false;
        if (self.pos + 8 > self.buf.len) return false;
        std.mem.writeInt(u64, self.buf[self.pos..][0..8], value, .little);
        self.pos += 8;
        return true;
    }

    fn writeDouble(self: *ProtoWriter, field_number: u32, value: f64) bool {
        return self.writeFixed64(field_number, @bitCast(value));
    }

    fn writeVarintField(self: *ProtoWriter, field_number: u32, value: u64) bool {
        if (value == 0) return true; // Skip default values
        if (!self.writeTag(field_number, VARINT)) return false;
        return self.writeVarint(value);
    }

    fn writeStringField(self: *ProtoWriter, field_number: u32, value: []const u8) bool {
        if (value.len == 0) return true;
        return self.writeLenDelimited(field_number, value);
    }
};

// ── Size calculators (for length-delimited submessages) ─────────────────
fn varintSize(value: u64) usize {
    if (value == 0) return 1;
    var v = value;
    var size: usize = 0;
    while (v > 0) {
        size += 1;
        v >>= 7;
    }
    return size;
}

// ── Encode a single KeyValue ────────────────────────────────────────────
fn encodeKeyValue(w: *ProtoWriter, attr: Attribute, field_num: u32) bool {
    var tmp_buf: [512]u8 = undefined;
    var tmp = ProtoWriter{ .buf = &tmp_buf };

    if (!tmp.writeStringField(field.kv_key, attr.key)) return false;

    var av_buf: [256]u8 = undefined;
    var av = ProtoWriter{ .buf = &av_buf };

    switch (attr.value) {
        .string => |s| {
            if (!av.writeStringField(field.av_string, s)) return false;
        },
        .bool_val => |b| {
            if (!av.writeTag(field.av_bool, VARINT)) return false;
            if (!av.writeVarint(if (b) 1 else 0)) return false;
        },
        .int_val => |i| {
            if (!av.writeTag(field.av_int, VARINT)) return false;
            if (!av.writeSignedVarint(i)) return false;
        },
        .double_val => |d| {
            if (!av.writeDouble(field.av_double, d)) return false;
        },
        .bytes => |b| {
            if (!av.writeLenDelimited(field.av_bytes, b)) return false;
        },
        .null_val => {},
    }

    if (av.pos > 0) {
        if (!tmp.writeLenDelimited(field.kv_value, av.buf[0..av.pos])) return false;
    }

    return w.writeLenDelimited(field_num, tmp.buf[0..tmp.pos]);
}

// ── Encode a single Event ───────────────────────────────────────────────
fn encodeEvent(w: *ProtoWriter, event: SpanEvent) bool {
    var tmp_buf: [2048]u8 = undefined;
    var tmp = ProtoWriter{ .buf = &tmp_buf };

    // time_unix_nano (field 1, fixed64)
    if (!tmp.writeFixed64(field.event_time, event.timestamp_ns)) return false;
    // name (field 2, string)
    if (!tmp.writeStringField(field.event_name, event.name)) return false;
    // attributes (field 3, repeated KeyValue)
    for (event.attributes.slice()) |attr| {
        if (!encodeKeyValue(&tmp, attr, field.event_attributes)) return false;
    }

    return w.writeLenDelimited(field.span_events, tmp.buf[0..tmp.pos]);
}

// ── Encode a single Span ────────────────────────────────────────────────
fn encodeSpan(w: *ProtoWriter, rec: *const SpanRecord) bool {
    var span_buf: [8192]u8 = undefined;
    var sw = ProtoWriter{ .buf = &span_buf };

    // trace_id (field 1, bytes, 16 bytes)
    const trace_bytes = rec.trace_id.toBytes();
    if (!sw.writeLenDelimited(field.span_trace_id, &trace_bytes)) return false;

    // span_id (field 2, bytes, 8 bytes)
    const span_bytes = rec.span_id.toBytes();
    if (!sw.writeLenDelimited(field.span_span_id, &span_bytes)) return false;

    // parent_span_id (field 4, bytes, 8 bytes) — only if non-zero
    if (!rec.parent_span_id.isZero()) {
        const parent_bytes = rec.parent_span_id.toBytes();
        if (!sw.writeLenDelimited(field.span_parent_span_id, &parent_bytes)) return false;
    }

    // name (field 5, string)
    if (!sw.writeStringField(field.span_name, rec.nameSlice())) return false;

    // kind (field 6, enum as varint) — OTel SpanKind is 1-indexed: INTERNAL=1, SERVER=2, etc.
    if (!sw.writeVarintField(field.span_kind, @as(u64, @intFromEnum(rec.kind)) + 1)) return false;

    // start_time_unix_nano (field 7, fixed64)
    if (!sw.writeFixed64(field.span_start_time, rec.start_time_ns)) return false;

    // end_time_unix_nano (field 8, fixed64)
    if (!sw.writeFixed64(field.span_end_time, rec.end_time_ns)) return false;

    // attributes (field 9, repeated KeyValue)
    for (rec.attributes.slice()) |attr| {
        if (!encodeKeyValue(&sw, attr, field.span_attributes)) return false;
    }

    // events (field 10, repeated Event)
    var i: u8 = 0;
    while (i < rec.event_count) : (i += 1) {
        if (!encodeEvent(&sw, rec.events[i])) return false;
    }

    // status (field 15) — only if not unset
    if (rec.status != .unset) {
        var status_buf: [64]u8 = undefined;
        var st = ProtoWriter{ .buf = &status_buf };
        if (!st.writeTag(field.status_code, VARINT)) return false;
        if (!st.writeVarint(@intFromEnum(rec.status))) return false;
        if (rec.statusDescriptionSlice()) |desc| {
            if (!st.writeStringField(field.status_message, desc)) return false;
        }
        if (!sw.writeLenDelimited(field.span_status, status_buf[0..st.pos])) return false;
    }

    return w.writeLenDelimited(field.scope_spans_spans, span_buf[0..sw.pos]);
}

// ── Public API ──────────────────────────────────────────────────────────

/// Encode a batch of SpanRecords into OTLP protobuf bytes.
/// Returns the encoded slice, or null if buffer too small.
pub fn encodeSpanBatch(
    spans: []const SpanRecord,
    resource_attrs: []const Attribute,
    buffer: []u8,
) ?[]u8 {
    var w = ProtoWriter{ .buf = buffer };

    // Build ResourceSpans submessage
    var rs_buf: [16384]u8 = undefined;
    var rs = ProtoWriter{ .buf = &rs_buf };

    // Resource (field 1)
    {
        var res_buf: [4096]u8 = undefined;
        var res = ProtoWriter{ .buf = &res_buf };
        for (resource_attrs) |attr| {
            if (!encodeKeyValue(&res, attr, field.resource_attributes)) return null;
        }
        if (res.pos > 0) {
            if (!rs.writeLenDelimited(field.resource, res.buf[0..res.pos])) return null;
        }
    }

    // ScopeSpans (field 2)
    {
        var ss_buf: [16384]u8 = undefined;
        var ss = ProtoWriter{ .buf = &ss_buf };

        // InstrumentationScope (field 1)
        {
            var scope_buf: [128]u8 = undefined;
            var sc = ProtoWriter{ .buf = &scope_buf };
            if (!sc.writeStringField(field.scope_name, "terra")) return null;
            if (!sc.writeStringField(field.scope_version, "1.0.0")) return null;
            if (!ss.writeLenDelimited(field.scope, scope_buf[0..sc.pos])) return null;
        }

        // Spans (field 2, repeated)
        for (spans) |*span_rec| {
            if (!encodeSpan(&ss, span_rec)) return null;
        }

        if (!rs.writeLenDelimited(field.scope_spans, ss.buf[0..ss.pos])) return null;
    }

    // Write ResourceSpans as field 1 of ExportTraceServiceRequest
    if (!w.writeLenDelimited(field.resource_spans, rs.buf[0..rs.pos])) return null;

    return w.buf[0..w.pos];
}

// ── Tests ───────────────────────────────────────────────────────────────
test "varintSize" {
    try std.testing.expectEqual(@as(usize, 1), varintSize(0));
    try std.testing.expectEqual(@as(usize, 1), varintSize(127));
    try std.testing.expectEqual(@as(usize, 2), varintSize(128));
    try std.testing.expectEqual(@as(usize, 10), varintSize(std.math.maxInt(u64)));
}

test "ProtoWriter writeVarint" {
    var buf: [16]u8 = undefined;
    var w = ProtoWriter{ .buf = &buf };

    try std.testing.expect(w.writeVarint(0));
    try std.testing.expectEqual(@as(u8, 0), buf[0]);
    try std.testing.expectEqual(@as(usize, 1), w.pos);
}

test "ProtoWriter writeVarint multi-byte" {
    var buf: [16]u8 = undefined;
    var w = ProtoWriter{ .buf = &buf };

    try std.testing.expect(w.writeVarint(300));
    try std.testing.expectEqual(@as(usize, 2), w.pos);
    try std.testing.expectEqual(@as(u8, 0xAC), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x02), buf[1]);
}

test "encodeSpanBatch empty" {
    var buf: [1024]u8 = undefined;
    const result = encodeSpanBatch(&[_]SpanRecord{}, &[_]Attribute{}, &buf);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.len > 0);
}

test "encodeSpanBatch single span" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 2 };
    rec.span_id = models.SpanID{ .id = 3 };
    rec.setName("gen_ai.inference");
    rec.start_time_ns = 1_000_000;
    rec.end_time_ns = 2_000_000;
    rec.kind = .client;
    rec.status = .ok;

    _ = rec.attributes.append(.{ .key = "gen_ai.request.model", .value = .{ .string = "gpt-4" } });

    var buf: [4096]u8 = undefined;
    const result = encodeSpanBatch(
        &[_]SpanRecord{rec},
        &[_]Attribute{.{ .key = "service.name", .value = .{ .string = "test-svc" } }},
        &buf,
    );
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.len > 20); // Should have meaningful content
}

test "encodeSpanBatch all attribute types" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 10, .lo = 20 };
    rec.span_id = models.SpanID{ .id = 30 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    _ = rec.attributes.append(.{ .key = "str", .value = .{ .string = "hello" } });
    _ = rec.attributes.append(.{ .key = "int", .value = .{ .int_val = 42 } });
    _ = rec.attributes.append(.{ .key = "dbl", .value = .{ .double_val = 3.14 } });
    _ = rec.attributes.append(.{ .key = "bool", .value = .{ .bool_val = true } });
    _ = rec.attributes.append(.{ .key = "bytes", .value = .{ .bytes = "raw" } });

    var buf: [4096]u8 = undefined;
    const result = encodeSpanBatch(&[_]SpanRecord{rec}, &[_]Attribute{}, &buf);
    try std.testing.expect(result != null);
}

test "encodeSpanBatch with events" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    rec.events[0] = .{
        .name = "exception",
        .timestamp_ns = 150,
        .attributes = .{},
    };
    _ = rec.events[0].attributes.append(.{ .key = "exception.type", .value = .{ .string = "RuntimeError" } });
    rec.event_count = 1;

    var buf: [4096]u8 = undefined;
    const result = encodeSpanBatch(&[_]SpanRecord{rec}, &[_]Attribute{}, &buf);
    try std.testing.expect(result != null);
}

test "encodeSpanBatch with status error" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;
    rec.status = .err;
    {
        const desc = "something failed";
        @memcpy(rec.status_description_buf[0..desc.len], desc);
        rec.status_description_len = desc.len;
    }

    var buf: [4096]u8 = undefined;
    const result = encodeSpanBatch(&[_]SpanRecord{rec}, &[_]Attribute{}, &buf);
    try std.testing.expect(result != null);
}

test "encodeSpanBatch buffer too small" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("gen_ai.inference");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    var buf: [4]u8 = undefined; // Too small
    const result = encodeSpanBatch(&[_]SpanRecord{rec}, &[_]Attribute{}, &buf);
    try std.testing.expect(result == null);
}

test "encodeSpanBatch max attributes span" {
    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    // Fill up to max attributes
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        _ = rec.attributes.append(.{ .key = "k", .value = .{ .int_val = @intCast(i) } });
    }

    var buf: [32768]u8 = undefined;
    const result = encodeSpanBatch(&[_]SpanRecord{rec}, &[_]Attribute{}, &buf);
    try std.testing.expect(result != null);
}
