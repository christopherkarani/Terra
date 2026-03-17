// Terra Zig Core — transport.zig
// TransportVTable, noop_transport, buffer_transport for testing.

const std = @import("std");

pub const SendResult = enum(c_int) {
    ok = 0,
    err = -1,
};

pub const SendFn = *const fn (data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int;
pub const FlushFn = *const fn (ctx: ?*anyopaque) callconv(.c) void;
pub const ShutdownFn = *const fn (ctx: ?*anyopaque) callconv(.c) void;

pub const TransportVTable = struct {
    send_fn: SendFn,
    flush_fn: FlushFn,
    shutdown_fn: ShutdownFn,
    context: ?*anyopaque = null,

    pub fn send(self: TransportVTable, data: []const u8) c_int {
        return self.send_fn(data.ptr, @intCast(data.len), self.context);
    }

    pub fn flush(self: TransportVTable) void {
        self.flush_fn(self.context);
    }

    pub fn shutdown(self: TransportVTable) void {
        self.shutdown_fn(self.context);
    }
};

// ── Noop Transport ──────────────────────────────────────────────────────
fn noopSend(_: [*]const u8, _: u32, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}

fn noopFlush(_: ?*anyopaque) callconv(.c) void {}
fn noopShutdown(_: ?*anyopaque) callconv(.c) void {}

pub const noop_transport = TransportVTable{
    .send_fn = noopSend,
    .flush_fn = noopFlush,
    .shutdown_fn = noopShutdown,
    .context = null,
};

// ── Buffer Transport (for testing) ──────────────────────────────────────
pub const BufferTransport = struct {
    allocator: std.mem.Allocator,
    captures: std.ArrayList([]u8) = .empty,
    send_count: usize = 0,
    fail_next: bool = false,

    pub fn init(allocator: std.mem.Allocator) BufferTransport {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferTransport) void {
        for (self.captures.items) |buf| {
            self.allocator.free(buf);
        }
        self.captures.deinit(self.allocator);
    }

    pub fn vtable(self: *BufferTransport) TransportVTable {
        return .{
            .send_fn = bufferSend,
            .flush_fn = noopFlush,
            .shutdown_fn = noopShutdown,
            .context = @ptrCast(self),
        };
    }

    fn bufferSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
        const self: *BufferTransport = @ptrCast(@alignCast(ctx orelse return -1));
        self.send_count += 1;

        if (self.fail_next) {
            self.fail_next = false;
            return -1;
        }

        const copy = self.allocator.alloc(u8, len) catch return -1;
        @memcpy(copy, data[0..len]);
        self.captures.append(self.allocator, copy) catch {
            self.allocator.free(copy);
            return -1;
        };
        return 0;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "noop transport send returns ok" {
    const result = noop_transport.send("hello");
    try std.testing.expectEqual(@as(c_int, 0), result);
}

test "noop transport flush and shutdown are safe" {
    noop_transport.flush();
    noop_transport.shutdown();
}

test "buffer transport captures sent data" {
    var bt = BufferTransport.init(std.testing.allocator);
    defer bt.deinit();

    const vt = bt.vtable();
    const result = vt.send("test payload");
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqual(@as(usize, 1), bt.captures.items.len);
    try std.testing.expectEqualStrings("test payload", bt.captures.items[0]);
}

test "buffer transport fail_next" {
    var bt = BufferTransport.init(std.testing.allocator);
    defer bt.deinit();

    bt.fail_next = true;
    const vt = bt.vtable();
    const result = vt.send("will fail");
    try std.testing.expectEqual(@as(c_int, -1), result);
    try std.testing.expectEqual(@as(usize, 0), bt.captures.items.len);
}

test "buffer transport send count" {
    var bt = BufferTransport.init(std.testing.allocator);
    defer bt.deinit();

    const vt = bt.vtable();
    _ = vt.send("a");
    _ = vt.send("b");
    try std.testing.expectEqual(@as(usize, 2), bt.send_count);
}
