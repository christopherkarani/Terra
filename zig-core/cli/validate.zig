// Terra CLI — validate.zig
// Structural validator for OTLP protobuf files on disk.
// Checks required fields, reports span/attribute/event counts.

const std = @import("std");

/// Validation result for a single span found in the file.
const SpanValidation = struct {
    has_trace_id: bool = false,
    has_span_id: bool = false,
    has_name: bool = false,
    has_start_time: bool = false,
    has_end_time: bool = false,
    attribute_count: u32 = 0,
    event_count: u32 = 0,
};

/// Summary of validation across all spans in the file.
const ValidationSummary = struct {
    total_spans: u32 = 0,
    total_attributes: u32 = 0,
    total_events: u32 = 0,
    missing_trace_id: u32 = 0,
    missing_span_id: u32 = 0,
    missing_name: u32 = 0,
    missing_start_time: u32 = 0,
    missing_end_time: u32 = 0,
    parse_errors: u32 = 0,
};

/// Protobuf wire types
const VARINT: u3 = 0;
const I64: u3 = 1;
const LEN: u3 = 2;
const I32: u3 = 5;

/// Read a varint from the buffer. Returns the value and bytes consumed, or null on error.
fn readVarint(data: []const u8) ?struct { value: u64, consumed: usize } {
    var result: u64 = 0;
    var shift: u6 = 0;
    for (data, 0..) |byte, i| {
        if (i >= 10) return null; // Varint too long
        result |= @as(u64, byte & 0x7F) << shift;
        if (byte & 0x80 == 0) {
            return .{ .value = result, .consumed = i + 1 };
        }
        shift +|= 7;
    }
    return null;
}

/// Skip a protobuf field based on wire type. Returns bytes consumed, or null on error.
fn skipField(data: []const u8, wire_type: u3) ?usize {
    switch (wire_type) {
        VARINT => {
            const v = readVarint(data) orelse return null;
            return v.consumed;
        },
        I64 => {
            if (data.len < 8) return null;
            return 8;
        },
        LEN => {
            const v = readVarint(data) orelse return null;
            const total = v.consumed + @as(usize, @intCast(v.value));
            if (total > data.len) return null;
            return total;
        },
        I32 => {
            if (data.len < 4) return null;
            return 4;
        },
        else => return null,
    }
}

/// Parse a length-delimited submessage, returning its content bytes.
fn parseLenDelimited(data: []const u8) ?struct { content: []const u8, consumed: usize } {
    const v = readVarint(data) orelse return null;
    const len: usize = @intCast(v.value);
    const start = v.consumed;
    if (start + len > data.len) return null;
    return .{
        .content = data[start .. start + len],
        .consumed = start + len,
    };
}

/// Validate a single Span submessage.
fn validateSpan(data: []const u8) SpanValidation {
    var result = SpanValidation{};
    var pos: usize = 0;

    while (pos < data.len) {
        const tag_v = readVarint(data[pos..]) orelse break;
        pos += tag_v.consumed;
        const field_number: u32 = @intCast(tag_v.value >> 3);
        const wire_type: u3 = @intCast(tag_v.value & 0x7);

        switch (field_number) {
            1 => { // trace_id (bytes)
                if (wire_type == LEN) {
                    const ld = parseLenDelimited(data[pos..]) orelse break;
                    if (ld.content.len == 16) result.has_trace_id = true;
                    pos += ld.consumed;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            2 => { // span_id (bytes)
                if (wire_type == LEN) {
                    const ld = parseLenDelimited(data[pos..]) orelse break;
                    if (ld.content.len == 8) result.has_span_id = true;
                    pos += ld.consumed;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            5 => { // name (string)
                if (wire_type == LEN) {
                    const ld = parseLenDelimited(data[pos..]) orelse break;
                    if (ld.content.len > 0) result.has_name = true;
                    pos += ld.consumed;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            7 => { // start_time_unix_nano (fixed64)
                if (wire_type == I64) {
                    if (pos + 8 <= data.len) {
                        result.has_start_time = true;
                        pos += 8;
                    } else break;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            8 => { // end_time_unix_nano (fixed64)
                if (wire_type == I64) {
                    if (pos + 8 <= data.len) {
                        result.has_end_time = true;
                        pos += 8;
                    } else break;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            9 => { // attributes (repeated KeyValue)
                if (wire_type == LEN) {
                    const ld = parseLenDelimited(data[pos..]) orelse break;
                    result.attribute_count += 1;
                    pos += ld.consumed;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            10 => { // events (repeated Event)
                if (wire_type == LEN) {
                    const ld = parseLenDelimited(data[pos..]) orelse break;
                    result.event_count += 1;
                    pos += ld.consumed;
                } else {
                    const skip = skipField(data[pos..], wire_type) orelse break;
                    pos += skip;
                }
            },
            else => {
                const skip = skipField(data[pos..], wire_type) orelse break;
                pos += skip;
            },
        }
    }

    return result;
}

/// Walk through a ScopeSpans submessage looking for Span submessages (field 2).
fn walkScopeSpans(data: []const u8, summary: *ValidationSummary) void {
    var pos: usize = 0;
    while (pos < data.len) {
        const tag_v = readVarint(data[pos..]) orelse break;
        pos += tag_v.consumed;
        const field_number: u32 = @intCast(tag_v.value >> 3);
        const wire_type: u3 = @intCast(tag_v.value & 0x7);

        if (field_number == 2 and wire_type == LEN) {
            const ld = parseLenDelimited(data[pos..]) orelse break;
            const sv = validateSpan(ld.content);
            summary.total_spans += 1;
            summary.total_attributes += sv.attribute_count;
            summary.total_events += sv.event_count;
            if (!sv.has_trace_id) summary.missing_trace_id += 1;
            if (!sv.has_span_id) summary.missing_span_id += 1;
            if (!sv.has_name) summary.missing_name += 1;
            if (!sv.has_start_time) summary.missing_start_time += 1;
            if (!sv.has_end_time) summary.missing_end_time += 1;
            pos += ld.consumed;
        } else {
            const skip = skipField(data[pos..], wire_type) orelse break;
            pos += skip;
        }
    }
}

/// Walk through a ResourceSpans submessage looking for ScopeSpans (field 2).
fn walkResourceSpans(data: []const u8, summary: *ValidationSummary) void {
    var pos: usize = 0;
    while (pos < data.len) {
        const tag_v = readVarint(data[pos..]) orelse break;
        pos += tag_v.consumed;
        const field_number: u32 = @intCast(tag_v.value >> 3);
        const wire_type: u3 = @intCast(tag_v.value & 0x7);

        if (field_number == 2 and wire_type == LEN) {
            const ld = parseLenDelimited(data[pos..]) orelse break;
            walkScopeSpans(ld.content, summary);
            pos += ld.consumed;
        } else {
            const skip = skipField(data[pos..], wire_type) orelse break;
            pos += skip;
        }
    }
}

/// Validate an OTLP ExportTraceServiceRequest from raw bytes.
pub fn validateOtlpBytes(data: []const u8) ValidationSummary {
    var summary = ValidationSummary{};
    var pos: usize = 0;

    while (pos < data.len) {
        const tag_v = readVarint(data[pos..]) orelse {
            summary.parse_errors += 1;
            break;
        };
        pos += tag_v.consumed;
        const field_number: u32 = @intCast(tag_v.value >> 3);
        const wire_type: u3 = @intCast(tag_v.value & 0x7);

        if (field_number == 1 and wire_type == LEN) {
            const ld = parseLenDelimited(data[pos..]) orelse {
                summary.parse_errors += 1;
                break;
            };
            walkResourceSpans(ld.content, &summary);
            pos += ld.consumed;
        } else {
            const skip = skipField(data[pos..], wire_type) orelse {
                summary.parse_errors += 1;
                break;
            };
            pos += skip;
        }
    }

    return summary;
}

pub fn run(args: []const []const u8) void {
    if (args.len == 0) {
        std.debug.print("\nUsage: terra validate <file.pb>\n\n", .{});
        std.debug.print("Validate an OTLP protobuf trace file.\n", .{});
        std.debug.print("Checks required fields: trace_id, span_id, name, timestamps.\n", .{});
        std.debug.print("Reports: span count, attribute count, event count, missing fields.\n\n", .{});
        return;
    }

    const file_path = args[0];

    // Read file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("Error: cannot open file '{s}': {s}\n", .{ file_path, @errorName(err) });
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("Error: cannot stat file: {s}\n", .{@errorName(err)});
        return;
    };

    if (stat.size > 10 * 1024 * 1024) {
        std.debug.print("Error: file too large ({d} bytes, max 10 MiB)\n", .{stat.size});
        return;
    }

    var buf: [10 * 1024 * 1024]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch |err| {
        std.debug.print("Error: cannot read file: {s}\n", .{@errorName(err)});
        return;
    };

    if (bytes_read == 0) {
        std.debug.print("Error: file is empty\n", .{});
        return;
    }

    const data = buf[0..bytes_read];

    std.debug.print("\n=== terra validate ===\n\n", .{});
    std.debug.print("File: {s}\n", .{file_path});
    std.debug.print("Size: {d} bytes\n\n", .{bytes_read});

    const summary = validateOtlpBytes(data);

    std.debug.print("--- Results ---\n", .{});
    std.debug.print("Spans found:         {d}\n", .{summary.total_spans});
    std.debug.print("Total attributes:    {d}\n", .{summary.total_attributes});
    std.debug.print("Total events:        {d}\n", .{summary.total_events});

    if (summary.parse_errors > 0) {
        std.debug.print("Parse errors:        {d}\n", .{summary.parse_errors});
    }

    const has_issues = summary.missing_trace_id > 0 or
        summary.missing_span_id > 0 or
        summary.missing_name > 0 or
        summary.missing_start_time > 0 or
        summary.missing_end_time > 0;

    if (has_issues) {
        std.debug.print("\n--- Missing Fields ---\n", .{});
        if (summary.missing_trace_id > 0)
            std.debug.print("Missing trace_id:    {d} spans\n", .{summary.missing_trace_id});
        if (summary.missing_span_id > 0)
            std.debug.print("Missing span_id:     {d} spans\n", .{summary.missing_span_id});
        if (summary.missing_name > 0)
            std.debug.print("Missing name:        {d} spans\n", .{summary.missing_name});
        if (summary.missing_start_time > 0)
            std.debug.print("Missing start_time:  {d} spans\n", .{summary.missing_start_time});
        if (summary.missing_end_time > 0)
            std.debug.print("Missing end_time:    {d} spans\n", .{summary.missing_end_time});
        std.debug.print("\nValidation: ISSUES FOUND\n\n", .{});
    } else if (summary.total_spans == 0) {
        std.debug.print("\nValidation: NO SPANS FOUND (file may not be OTLP protobuf)\n\n", .{});
    } else {
        std.debug.print("\nValidation: OK\n\n", .{});
    }
}

// ── Tests ───────────────────────────────────────────────────────────────

test "readVarint single byte" {
    const data = [_]u8{0x08};
    const result = readVarint(&data);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 8), result.?.value);
    try std.testing.expectEqual(@as(usize, 1), result.?.consumed);
}

test "readVarint multi-byte" {
    const data = [_]u8{ 0xAC, 0x02 };
    const result = readVarint(&data);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 300), result.?.value);
    try std.testing.expectEqual(@as(usize, 2), result.?.consumed);
}

test "readVarint empty input" {
    const data = [_]u8{};
    const result = readVarint(&data);
    try std.testing.expect(result == null);
}

test "validateOtlpBytes with Terra-encoded span" {
    // Use Terra's own OTLP encoder to produce valid protobuf
    const terra_lib = @import("terra");
    const otlp = terra_lib.otlp;
    const models = terra_lib.models;

    var rec = models.SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 2 };
    rec.span_id = models.SpanID{ .id = 3 };
    rec.setName("gen_ai.inference");
    rec.start_time_ns = 1_000_000;
    rec.end_time_ns = 2_000_000;
    rec.kind = .client;

    _ = rec.attributes.append(.{ .key = "gen_ai.request.model", .value = .{ .string = "gpt-4" } });

    var buf: [4096]u8 = undefined;
    const encoded = otlp.encodeSpanBatch(
        &[_]models.SpanRecord{rec},
        &[_]models.Attribute{.{ .key = "service.name", .value = .{ .string = "test" } }},
        &buf,
    );
    try std.testing.expect(encoded != null);

    const summary = validateOtlpBytes(encoded.?);
    try std.testing.expectEqual(@as(u32, 1), summary.total_spans);
    try std.testing.expectEqual(@as(u32, 0), summary.missing_trace_id);
    try std.testing.expectEqual(@as(u32, 0), summary.missing_span_id);
    try std.testing.expectEqual(@as(u32, 0), summary.missing_name);
    try std.testing.expectEqual(@as(u32, 0), summary.missing_start_time);
    try std.testing.expectEqual(@as(u32, 0), summary.missing_end_time);
    try std.testing.expectEqual(@as(u32, 1), summary.total_attributes);
    try std.testing.expectEqual(@as(u32, 0), summary.parse_errors);
}

test "validateOtlpBytes empty data" {
    const summary = validateOtlpBytes(&[_]u8{});
    try std.testing.expectEqual(@as(u32, 0), summary.total_spans);
    try std.testing.expectEqual(@as(u32, 0), summary.parse_errors);
}

test "validateOtlpBytes garbage data" {
    const garbage = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF };
    const summary = validateOtlpBytes(&garbage);
    // Should not crash, may report parse errors
    _ = summary;
}

test "skipField varint" {
    const data = [_]u8{ 0xAC, 0x02 };
    const result = skipField(&data, VARINT);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?);
}

test "skipField fixed64" {
    const data = [_]u8{0} ** 8;
    const result = skipField(&data, I64);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 8), result.?);
}

test "skipField len-delimited" {
    // Length prefix = 3, then 3 bytes of content
    const data = [_]u8{ 0x03, 0x41, 0x42, 0x43 };
    const result = skipField(&data, LEN);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 4), result.?);
}

test "run with no args prints usage" {
    // Smoke test: just verify no crash
    run(&[_][]const u8{});
}
