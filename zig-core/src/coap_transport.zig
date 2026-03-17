// Terra Zig Core — coap_transport.zig
// CoAP (Constrained Application Protocol) transport stub for MCU/IoT deployments.
//
// Wire format: CoAP over UDP (RFC 7252)
// ┌──────────────────────────────────────────────────┐
// │ CoAP Header (4 bytes)                            │
// │  Ver(2) | Type(2) | TKL(4) | Code(8) | MsgID(16)│
// ├──────────────────────────────────────────────────┤
// │ Token (0-8 bytes, length = TKL)                  │
// ├──────────────────────────────────────────────────┤
// │ Options (variable, delta-encoded)                │
// │  - Uri-Path: /v1/traces                          │
// │  - Content-Format: application/octet-stream (42) │
// ├──────────────────────────────────────────────────┤
// │ 0xFF (payload marker)                            │
// ├──────────────────────────────────────────────────┤
// │ Payload (OTLP protobuf bytes)                    │
// └──────────────────────────────────────────────────┘
//
// Actual UDP socket implementation is deferred — this provides the framing
// and TransportVTable interface so MCU firmware can wire in a platform-specific
// UDP send function.

const transport = @import("transport.zig");

// ── CoAP Constants ──────────────────────────────────────────────────────
pub const COAP_VERSION: u2 = 1;

pub const MessageType = enum(u2) {
    confirmable = 0,
    non_confirmable = 1,
    acknowledgement = 2,
    reset = 3,
};

pub const Code = struct {
    pub const POST: u8 = 0x02; // 0.02
    pub const CREATED: u8 = 0x41; // 2.01
    pub const BAD_REQUEST: u8 = 0x80; // 4.00
    pub const NOT_FOUND: u8 = 0x84; // 4.04
    pub const INTERNAL_ERROR: u8 = 0xA0; // 5.00
};

pub const ContentFormat = struct {
    pub const OCTET_STREAM: u16 = 42;
    pub const CBOR: u16 = 60;
};

// ── CoAP Header ─────────────────────────────────────────────────────────
pub const Header = struct {
    version: u2 = COAP_VERSION,
    msg_type: MessageType = .non_confirmable,
    token_len: u4 = 0,
    code: u8 = Code.POST,
    message_id: u16 = 0,

    /// Serialize header to 4 bytes (big-endian).
    pub fn toBytes(self: Header) [4]u8 {
        var buf: [4]u8 = undefined;
        buf[0] = (@as(u8, self.version) << 6) |
            (@as(u8, @intFromEnum(self.msg_type)) << 4) |
            @as(u8, self.token_len);
        buf[1] = self.code;
        buf[2] = @truncate(self.message_id >> 8);
        buf[3] = @truncate(self.message_id);
        return buf;
    }

    /// Parse header from 4 bytes.
    pub fn fromBytes(bytes: [4]u8) Header {
        return .{
            .version = @truncate(bytes[0] >> 6),
            .msg_type = @enumFromInt(@as(u2, @truncate(bytes[0] >> 4))),
            .token_len = @truncate(bytes[0]),
            .code = bytes[1],
            .message_id = (@as(u16, bytes[2]) << 8) | @as(u16, bytes[3]),
        };
    }
};

// ── CoAP Frame Builder ──────────────────────────────────────────────────
/// Build a CoAP POST frame for /v1/traces with OTLP payload.
/// Writes into `out_buf`, returns the slice of written bytes, or null if buffer too small.
pub fn buildTraceFrame(
    payload: []const u8,
    message_id: u16,
    out_buf: []u8,
) ?[]const u8 {
    // Minimum: 4 (header) + 1 (uri-path option) + 4 ("v1") + 1 + 7 ("traces")
    //        + 3 (content-format option) + 1 (payload marker) + payload
    const header = Header{
        .msg_type = .non_confirmable,
        .code = Code.POST,
        .message_id = message_id,
    };

    var pos: usize = 0;

    // Header (4 bytes)
    if (pos + 4 > out_buf.len) return null;
    const hdr_bytes = header.toBytes();
    @memcpy(out_buf[pos..][0..4], &hdr_bytes);
    pos += 4;

    // Option: Uri-Path "v1" (option number 11, delta 11)
    if (pos + 3 > out_buf.len) return null;
    out_buf[pos] = (11 << 4) | 2; // delta=11, length=2
    pos += 1;
    out_buf[pos] = 'v';
    pos += 1;
    out_buf[pos] = '1';
    pos += 1;

    // Option: Uri-Path "traces" (option number 11, delta 0)
    if (pos + 7 > out_buf.len) return null;
    out_buf[pos] = (0 << 4) | 6; // delta=0, length=6
    pos += 1;
    @memcpy(out_buf[pos..][0..6], "traces");
    pos += 6;

    // Option: Content-Format (option number 12, delta 1)
    // Value: 42 (application/octet-stream), encoded as 1 byte
    if (pos + 2 > out_buf.len) return null;
    out_buf[pos] = (1 << 4) | 1; // delta=1, length=1
    pos += 1;
    out_buf[pos] = 42; // octet-stream
    pos += 1;

    // Payload marker
    if (pos + 1 + payload.len > out_buf.len) return null;
    out_buf[pos] = 0xFF;
    pos += 1;

    // Payload
    @memcpy(out_buf[pos..][0..payload.len], payload);
    pos += payload.len;

    return out_buf[0..pos];
}

// ── CoAP Transport Context ──────────────────────────────────────────────
/// Platform-specific UDP send function signature.
/// The MCU firmware provides this. Returns 0 on success, non-zero on error.
pub const UdpSendFn = *const fn (data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int;

pub const CoapTransportConfig = struct {
    /// Platform-provided UDP send function.
    udp_send: UdpSendFn,
    /// Opaque context passed to udp_send (e.g., socket handle, destination address).
    udp_ctx: ?*anyopaque = null,
    /// CoAP message ID counter (incremented per frame).
    next_message_id: u16 = 1,
};

/// Frame buffer for CoAP packet assembly. Sized for typical MCU constraints.
const COAP_FRAME_BUF_SIZE = 2048;

// ── TransportVTable implementation ──────────────────────────────────────
fn coapSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *CoapTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));

    var frame_buf: [COAP_FRAME_BUF_SIZE]u8 = undefined;
    const frame = buildTraceFrame(
        data[0..len],
        cfg.next_message_id,
        &frame_buf,
    ) orelse return -1;

    cfg.next_message_id +%= 1;

    return cfg.udp_send(frame.ptr, @intCast(frame.len), cfg.udp_ctx);
}

fn coapFlush(_: ?*anyopaque) callconv(.c) void {
    // CoAP is message-oriented — nothing to flush.
}

fn coapShutdown(_: ?*anyopaque) callconv(.c) void {
    // No persistent connection to tear down.
}

/// Create a TransportVTable backed by CoAP framing over a platform-provided UDP send.
pub fn vtable(cfg: *CoapTransportConfig) transport.TransportVTable {
    return .{
        .send_fn = coapSend,
        .flush_fn = coapFlush,
        .shutdown_fn = coapShutdown,
        .context = @ptrCast(cfg),
    };
}

// ── Tests ───────────────────────────────────────────────────────────────
const std = @import("std");

test "CoAP Header round-trip" {
    const hdr = Header{
        .version = 1,
        .msg_type = .non_confirmable,
        .token_len = 0,
        .code = Code.POST,
        .message_id = 0x1234,
    };
    const bytes = hdr.toBytes();
    const parsed = Header.fromBytes(bytes);
    try std.testing.expectEqual(hdr.version, parsed.version);
    try std.testing.expectEqual(hdr.msg_type, parsed.msg_type);
    try std.testing.expectEqual(hdr.code, parsed.code);
    try std.testing.expectEqual(hdr.message_id, parsed.message_id);
}

test "CoAP buildTraceFrame produces valid frame" {
    const payload = "test-otlp-data";
    var buf: [256]u8 = undefined;
    const frame = buildTraceFrame(payload, 42, &buf);
    try std.testing.expect(frame != null);

    const f = frame.?;
    // Minimum size: 4 (header) + options + 1 (marker) + payload
    try std.testing.expect(f.len > 4 + payload.len);

    // Check header bytes
    const hdr = Header.fromBytes(f[0..4].*);
    try std.testing.expectEqual(COAP_VERSION, hdr.version);
    try std.testing.expectEqual(MessageType.non_confirmable, hdr.msg_type);
    try std.testing.expectEqual(Code.POST, hdr.code);
    try std.testing.expectEqual(@as(u16, 42), hdr.message_id);

    // Find payload marker (0xFF)
    var marker_pos: ?usize = null;
    for (f, 0..) |b, i| {
        if (i >= 4 and b == 0xFF) {
            marker_pos = i;
            break;
        }
    }
    try std.testing.expect(marker_pos != null);

    // Check payload after marker
    const payload_start = marker_pos.? + 1;
    try std.testing.expectEqualStrings(payload, f[payload_start..]);
}

test "CoAP buildTraceFrame buffer too small" {
    const payload = "test-data";
    var buf: [4]u8 = undefined; // Too small
    const frame = buildTraceFrame(payload, 1, &buf);
    try std.testing.expect(frame == null);
}

test "CoAP vtable creation" {
    var cfg = CoapTransportConfig{
        .udp_send = testUdpSend,
        .udp_ctx = null,
    };
    const vt = vtable(&cfg);
    // Verify the vtable has our functions wired
    try std.testing.expect(vt.send_fn == coapSend);
    try std.testing.expect(vt.flush_fn == coapFlush);
    try std.testing.expect(vt.shutdown_fn == coapShutdown);
}

test "CoAP transport send via vtable" {
    var send_called = false;
    var cfg = CoapTransportConfig{
        .udp_send = testUdpSendTracking,
        .udp_ctx = @ptrCast(&send_called),
    };
    const vt = vtable(&cfg);
    const result = vt.send("hello");
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expect(send_called);
}

fn testUdpSend(_: [*]const u8, _: u32, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

fn testUdpSendTracking(_: [*]const u8, _: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    if (ctx) |c| {
        const flag: *bool = @ptrCast(@alignCast(c));
        flag.* = true;
    }
    return 0;
}
