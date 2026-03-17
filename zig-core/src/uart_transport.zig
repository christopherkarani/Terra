// Terra Zig Core — uart_transport.zig
// UART transport with length-prefix + CRC16 framing for serial interfaces (drones, robots).
//
// Wire format per frame:
// ┌──────────────────────────────────────────────────────────────┐
// │ [0x54 0x52] magic ("TR")                          2 bytes   │
// │ [length]    payload length as u16 little-endian    2 bytes   │
// │ [payload]   raw OTLP bytes                        N bytes   │
// │ [crc16]     CRC-16/CCITT of payload               2 bytes   │
// └──────────────────────────────────────────────────────────────┘
//
// Maximum payload: 4096 bytes (configurable via MAX_PAYLOAD_SIZE).
// The platform provides a UartWriteFn for the actual serial I/O.

const std = @import("std");
const transport = @import("transport.zig");

// ── Constants ─────────────────────────────────────────────────────────────
pub const MAGIC: [2]u8 = .{ 0x54, 0x52 }; // "TR"
pub const FRAME_OVERHEAD = 2 + 2 + 2; // magic + length + crc
pub const MAX_PAYLOAD_SIZE: u16 = 4096;

// ── CRC-16/CCITT ──────────────────────────────────────────────────────────
/// CRC-16/CCITT (polynomial 0x1021, init 0xFFFF).
/// Also known as CRC-16/KERMIT variant with 0xFFFF seed.
pub fn crc16_ccitt(data: []const u8) u16 {
    var crc: u16 = 0xFFFF;
    for (data) |byte| {
        crc ^= @as(u16, byte) << 8;
        for (0..8) |_| {
            if (crc & 0x8000 != 0) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc = crc << 1;
            }
        }
    }
    return crc;
}

// ── Frame Builder ─────────────────────────────────────────────────────────
/// Build a framed UART message into `out`.
/// Returns the slice of written bytes, or null if:
/// - payload exceeds MAX_PAYLOAD_SIZE
/// - output buffer is too small
pub fn buildFrame(payload: []const u8, out: []u8) ?[]u8 {
    if (payload.len > MAX_PAYLOAD_SIZE) return null;

    const total = FRAME_OVERHEAD + payload.len;
    if (out.len < total) return null;

    // Magic
    out[0] = MAGIC[0];
    out[1] = MAGIC[1];

    // Length (u16 little-endian)
    const len16: u16 = @intCast(payload.len);
    out[2] = @truncate(len16);
    out[3] = @truncate(len16 >> 8);

    // Payload
    @memcpy(out[4..][0..payload.len], payload);

    // CRC-16/CCITT of payload
    const crc = crc16_ccitt(payload);
    const crc_offset = 4 + payload.len;
    out[crc_offset] = @truncate(crc);
    out[crc_offset + 1] = @truncate(crc >> 8);

    return out[0..total];
}

// ── Frame Parser ──────────────────────────────────────────────────────────
pub const ParsedFrame = struct {
    payload: []const u8,
};

/// Validate and extract payload from a framed UART message.
/// Returns null if:
/// - data too short for minimum frame
/// - magic bytes don't match
/// - length exceeds available data
/// - CRC mismatch
pub fn parseFrame(data: []const u8) ?ParsedFrame {
    // Minimum frame: magic(2) + length(2) + crc(2) = 6 bytes (empty payload)
    if (data.len < FRAME_OVERHEAD) return null;

    // Check magic
    if (data[0] != MAGIC[0] or data[1] != MAGIC[1]) return null;

    // Read length (u16 little-endian)
    const payload_len: u16 = @as(u16, data[2]) | (@as(u16, data[3]) << 8);
    if (payload_len > MAX_PAYLOAD_SIZE) return null;

    const total = FRAME_OVERHEAD + @as(usize, payload_len);
    if (data.len < total) return null;

    const payload = data[4..][0..payload_len];

    // Verify CRC
    const expected_crc = crc16_ccitt(payload);
    const crc_offset = 4 + @as(usize, payload_len);
    const actual_crc: u16 = @as(u16, data[crc_offset]) | (@as(u16, data[crc_offset + 1]) << 8);

    if (expected_crc != actual_crc) return null;

    return .{ .payload = payload };
}

// ── UART Transport VTable ─────────────────────────────────────────────────
/// Platform-provided UART write function signature.
/// The firmware provides this. Returns 0 on success, non-zero on error.
pub const UartWriteFn = *const fn (data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int;

pub const UartTransportConfig = struct {
    /// Platform-provided UART write function.
    uart_write: UartWriteFn,
    /// Opaque context passed to uart_write (e.g., UART peripheral handle).
    uart_ctx: ?*anyopaque = null,
};

/// Internal frame buffer for UART packet assembly.
const UART_FRAME_BUF_SIZE = FRAME_OVERHEAD + MAX_PAYLOAD_SIZE;

fn uartSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *UartTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));

    var frame_buf: [UART_FRAME_BUF_SIZE]u8 = undefined;
    const frame = buildFrame(data[0..len], &frame_buf) orelse return -1;

    return cfg.uart_write(frame.ptr, @intCast(frame.len), cfg.uart_ctx);
}

fn uartFlush(_: ?*anyopaque) callconv(.c) void {
    // UART is byte-oriented — nothing to flush at this layer.
}

fn uartShutdown(_: ?*anyopaque) callconv(.c) void {
    // No persistent connection to tear down.
}

/// Create a TransportVTable backed by UART framing over a platform-provided write function.
pub fn vtable(cfg: *UartTransportConfig) transport.TransportVTable {
    return .{
        .send_fn = uartSend,
        .flush_fn = uartFlush,
        .shutdown_fn = uartShutdown,
        .context = @ptrCast(cfg),
    };
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "CRC-16/CCITT known vector: empty" {
    // CRC-16/CCITT with init 0xFFFF and poly 0x1021 of empty string = 0xFFFF
    const crc = crc16_ccitt("");
    try std.testing.expectEqual(@as(u16, 0xFFFF), crc);
}

test "CRC-16/CCITT known vector: 123456789" {
    // Standard test vector: CRC-16/CCITT of "123456789" = 0x29B1
    const crc = crc16_ccitt("123456789");
    try std.testing.expectEqual(@as(u16, 0x29B1), crc);
}

test "CRC-16/CCITT known vector: single byte" {
    // CRC of "A" (0x41): init=0xFFFF, XOR 0x41<<8 = 0xBEFF, then 8 shifts with poly
    const crc = crc16_ccitt("A");
    try std.testing.expectEqual(@as(u16, 0xB915), crc);
}

test "CRC-16/CCITT deterministic" {
    const data = "hello terra";
    const crc1 = crc16_ccitt(data);
    const crc2 = crc16_ccitt(data);
    try std.testing.expectEqual(crc1, crc2);
}

test "buildFrame and parseFrame round-trip" {
    const payload = "test-otlp-data";
    var buf: [256]u8 = undefined;

    const frame = buildFrame(payload, &buf);
    try std.testing.expect(frame != null);

    const f = frame.?;
    // Verify frame size: 2 magic + 2 length + 14 payload + 2 crc = 20
    try std.testing.expectEqual(@as(usize, 20), f.len);

    // Parse it back
    const parsed = parseFrame(f);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqualStrings(payload, parsed.?.payload);
}

test "buildFrame empty payload round-trip" {
    var buf: [16]u8 = undefined;
    const frame = buildFrame("", &buf);
    try std.testing.expect(frame != null);

    const f = frame.?;
    try std.testing.expectEqual(@as(usize, FRAME_OVERHEAD), f.len);

    const parsed = parseFrame(f);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(usize, 0), parsed.?.payload.len);
}

test "buildFrame payload too large" {
    var buf: [8192]u8 = undefined;
    const huge = &([_]u8{0xAA} ** (MAX_PAYLOAD_SIZE + 1));
    const frame = buildFrame(huge, &buf);
    try std.testing.expect(frame == null);
}

test "buildFrame buffer too small" {
    var buf: [4]u8 = undefined; // Too small for any frame
    const frame = buildFrame("hi", &buf);
    try std.testing.expect(frame == null);
}

test "parseFrame too short" {
    const data = [_]u8{ 0x54, 0x52, 0x00 }; // Only 3 bytes
    try std.testing.expect(parseFrame(&data) == null);
}

test "parseFrame bad magic" {
    var buf: [256]u8 = undefined;
    const frame = buildFrame("data", &buf).?;

    // Corrupt magic byte
    var corrupted: [256]u8 = undefined;
    @memcpy(corrupted[0..frame.len], frame);
    corrupted[0] = 0xFF;
    try std.testing.expect(parseFrame(corrupted[0..frame.len]) == null);
}

test "parseFrame corrupt CRC" {
    var buf: [256]u8 = undefined;
    const frame = buildFrame("data", &buf).?;

    // Corrupt CRC (last 2 bytes)
    var corrupted: [256]u8 = undefined;
    @memcpy(corrupted[0..frame.len], frame);
    corrupted[frame.len - 1] ^= 0xFF;
    try std.testing.expect(parseFrame(corrupted[0..frame.len]) == null);
}

test "parseFrame corrupt payload detected by CRC" {
    var buf: [256]u8 = undefined;
    const frame = buildFrame("payload-data", &buf).?;

    // Corrupt a payload byte
    var corrupted: [256]u8 = undefined;
    @memcpy(corrupted[0..frame.len], frame);
    corrupted[5] ^= 0x01; // flip a bit in payload
    try std.testing.expect(parseFrame(corrupted[0..frame.len]) == null);
}

test "parseFrame length exceeds data" {
    // Valid magic, but length field claims more data than available
    const data = [_]u8{ 0x54, 0x52, 0xFF, 0x00, 0x00, 0x00 }; // length=255 but only 2 bytes of "payload+crc"
    try std.testing.expect(parseFrame(&data) == null);
}

test "UART vtable creation" {
    var cfg = UartTransportConfig{
        .uart_write = testUartWrite,
        .uart_ctx = null,
    };
    const vt = vtable(&cfg);
    try std.testing.expect(vt.send_fn == uartSend);
    try std.testing.expect(vt.flush_fn == uartFlush);
    try std.testing.expect(vt.shutdown_fn == uartShutdown);
}

test "UART transport send via vtable" {
    var send_called = false;
    var cfg = UartTransportConfig{
        .uart_write = testUartWriteTracking,
        .uart_ctx = @ptrCast(&send_called),
    };
    const vt = vtable(&cfg);
    const result = vt.send("hello-uart");
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expect(send_called);
}

test "UART transport send null context returns error" {
    const result = uartSend("x".ptr, 1, null);
    try std.testing.expectEqual(@as(c_int, -1), result);
}

test "UART max payload builds successfully" {
    const payload = &([_]u8{0xBB} ** MAX_PAYLOAD_SIZE);
    var buf: [UART_FRAME_BUF_SIZE]u8 = undefined;
    const frame = buildFrame(payload, &buf);
    try std.testing.expect(frame != null);

    const parsed = parseFrame(frame.?);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqual(@as(usize, MAX_PAYLOAD_SIZE), parsed.?.payload.len);
}

// ── Test helpers ──────────────────────────────────────────────────────────
fn testUartWrite(_: [*]const u8, _: u32, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

fn testUartWriteTracking(_: [*]const u8, _: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    if (ctx) |c| {
        const flag: *bool = @ptrCast(@alignCast(c));
        flag.* = true;
    }
    return 0;
}
