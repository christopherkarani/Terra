// Terra Zig Core — http_transport.zig
// HTTP transport implementing TransportVTable using Zig's std.http.Client.
// Sends OTLP protobuf data via HTTP POST.

const std = @import("std");
const transport = @import("transport.zig");
const TransportVTable = transport.TransportVTable;

/// HTTP transport configuration.
pub const HttpTransportConfig = struct {
    /// OTLP endpoint URL (e.g. "http://localhost:4318/v1/traces").
    endpoint: []const u8 = "http://localhost:4318/v1/traces",
    /// Allocator for HTTP client internals.
    allocator: std.mem.Allocator = std.heap.page_allocator,
};

/// HTTP transport state. Caller owns and must call `deinit` when done.
pub const HttpTransport = struct {
    config: HttpTransportConfig,
    client: std.http.Client,
    send_count: usize = 0,
    last_status: ?std.http.Status = null,
    degraded: bool = false,

    pub fn init(cfg: HttpTransportConfig) HttpTransport {
        return .{
            .config = cfg,
            .client = .{ .allocator = cfg.allocator },
        };
    }

    pub fn deinit(self: *HttpTransport) void {
        self.client.deinit();
    }

    /// Returns a TransportVTable backed by this HttpTransport instance.
    pub fn vtable(self: *HttpTransport) TransportVTable {
        return .{
            .send_fn = httpSend,
            .flush_fn = httpFlush,
            .shutdown_fn = httpShutdown,
            .context = @ptrCast(self),
        };
    }

    /// Perform an HTTP POST with the given protobuf payload.
    /// Returns 0 on success (HTTP 2xx), -1 on failure.
    fn doSend(self: *HttpTransport, data: []const u8) c_int {
        const result = self.client.fetch(.{
            .location = .{ .url = self.config.endpoint },
            .method = .POST,
            .payload = data,
            .headers = .{
                .content_type = .{ .override = "application/x-protobuf" },
                .user_agent = .{ .override = "terra-zig/1.0.0" },
            },
            .keep_alive = true,
        });

        if (result) |res| {
            self.last_status = res.status;
            self.send_count += 1;
            const code = @intFromEnum(res.status);
            if (code >= 200 and code < 300) {
                self.degraded = false;
                return 0;
            }
            // Non-2xx response
            self.degraded = true;
            return -1;
        } else |_| {
            self.degraded = true;
            self.send_count += 1;
            return -1;
        }
    }
};

// ── C-ABI callbacks ─────────────────────────────────────────────────────

fn httpSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const self: *HttpTransport = @ptrCast(@alignCast(ctx orelse return -1));
    return self.doSend(data[0..len]);
}

fn httpFlush(_: ?*anyopaque) callconv(.c) void {
    // HTTP transport is request-per-send, no buffering to flush.
}

fn httpShutdown(ctx: ?*anyopaque) callconv(.c) void {
    const self: *HttpTransport = @ptrCast(@alignCast(ctx orelse return));
    self.client.deinit();
    // Re-init to a valid but empty state (safe for double-shutdown).
    self.client = .{ .allocator = self.config.allocator };
}

// ── Tests ───────────────────────────────────────────────────────────────

test "HttpTransport init and deinit" {
    var ht = HttpTransport.init(.{
        .endpoint = "http://localhost:4318/v1/traces",
        .allocator = std.testing.allocator,
    });
    defer ht.deinit();

    try std.testing.expectEqual(false, ht.degraded);
    try std.testing.expectEqual(@as(usize, 0), ht.send_count);
}

test "HttpTransport vtable returns valid function pointers" {
    var ht = HttpTransport.init(.{
        .endpoint = "http://localhost:4318/v1/traces",
        .allocator = std.testing.allocator,
    });
    defer ht.deinit();

    const vt = ht.vtable();
    try std.testing.expect(vt.send_fn != transport.noop_transport.send_fn);
    try std.testing.expect(vt.context != null);
}

test "HttpTransport send to unreachable host returns error" {
    var ht = HttpTransport.init(.{
        // Use a non-routable address to ensure fast failure
        .endpoint = "http://192.0.2.1:1/v1/traces",
        .allocator = std.testing.allocator,
    });
    defer ht.deinit();

    const vt = ht.vtable();
    const result = vt.send("test payload");
    // Should fail — no server running at this address
    try std.testing.expectEqual(@as(c_int, -1), result);
    try std.testing.expect(ht.degraded);
    try std.testing.expectEqual(@as(usize, 1), ht.send_count);
}

test "HttpTransport flush and shutdown are safe" {
    var ht = HttpTransport.init(.{
        .endpoint = "http://localhost:4318/v1/traces",
        .allocator = std.testing.allocator,
    });
    // Don't defer deinit — shutdown + deinit should be safe together
    const vt = ht.vtable();
    vt.flush();
    vt.shutdown();
    ht.deinit(); // Should be safe after shutdown
}

test "HttpTransport null context is safe" {
    const result = httpSend("data".ptr, 4, null);
    try std.testing.expectEqual(@as(c_int, -1), result);
}
