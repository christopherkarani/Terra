// Terra Zig Core — storage.zig
// StorageVTable, file_storage, noop_storage.

const std = @import("std");

pub const WriteFn = *const fn (data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int;
pub const ReadFn = *const fn (buf: [*]u8, max_len: u32, ctx: ?*anyopaque) callconv(.c) u32;
pub const DiscardOldestFn = *const fn (bytes: u32, ctx: ?*anyopaque) callconv(.c) void;
pub const AvailableBytesFn = *const fn (ctx: ?*anyopaque) callconv(.c) u64;

pub const StorageVTable = struct {
    write_fn: WriteFn,
    read_fn: ReadFn,
    discard_oldest_fn: DiscardOldestFn,
    available_bytes_fn: AvailableBytesFn,
    context: ?*anyopaque = null,

    pub fn write(self: StorageVTable, data: []const u8) c_int {
        return self.write_fn(data.ptr, @intCast(data.len), self.context);
    }

    pub fn read(self: StorageVTable, buf: []u8) u32 {
        return self.read_fn(buf.ptr, @intCast(buf.len), self.context);
    }

    pub fn discardOldest(self: StorageVTable, bytes: u32) void {
        self.discard_oldest_fn(bytes, self.context);
    }

    pub fn availableBytes(self: StorageVTable) u64 {
        return self.available_bytes_fn(self.context);
    }
};

// ── Noop Storage ────────────────────────────────────────────────────────
fn noopWrite(_: [*]const u8, _: u32, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
fn noopRead(_: [*]u8, _: u32, _: ?*anyopaque) callconv(.c) u32 {
    return 0;
}
fn noopDiscard(_: u32, _: ?*anyopaque) callconv(.c) void {}
fn noopAvailable(_: ?*anyopaque) callconv(.c) u64 {
    return 0;
}

pub const noop_storage = StorageVTable{
    .write_fn = noopWrite,
    .read_fn = noopRead,
    .discard_oldest_fn = noopDiscard,
    .available_bytes_fn = noopAvailable,
    .context = null,
};

// ── Buffer Storage (for testing) ────────────────────────────────────────
pub const BufferStorage = struct {
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8) = .empty,
    write_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) BufferStorage {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferStorage) void {
        self.data.deinit(self.allocator);
    }

    pub fn vtable(self: *BufferStorage) StorageVTable {
        return .{
            .write_fn = bufWrite,
            .read_fn = bufRead,
            .discard_oldest_fn = bufDiscard,
            .available_bytes_fn = bufAvailable,
            .context = @ptrCast(self),
        };
    }

    fn bufWrite(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
        const self: *BufferStorage = @ptrCast(@alignCast(ctx orelse return -1));
        self.write_count += 1;
        self.data.appendSlice(self.allocator, data[0..len]) catch return -1;
        return 0;
    }

    fn bufRead(buf: [*]u8, max_len: u32, ctx: ?*anyopaque) callconv(.c) u32 {
        const self: *BufferStorage = @ptrCast(@alignCast(ctx orelse return 0));
        const read_len = @min(@as(u32, @intCast(self.data.items.len)), max_len);
        @memcpy(buf[0..read_len], self.data.items[0..read_len]);
        return read_len;
    }

    fn bufDiscard(bytes: u32, ctx: ?*anyopaque) callconv(.c) void {
        const self: *BufferStorage = @ptrCast(@alignCast(ctx orelse return));
        const discard_len = @min(bytes, @as(u32, @intCast(self.data.items.len)));
        if (discard_len > 0) {
            const remaining = self.data.items.len - discard_len;
            std.mem.copyForwards(u8, self.data.items[0..remaining], self.data.items[discard_len..self.data.items.len]);
            self.data.shrinkRetainingCapacity(remaining);
        }
    }

    fn bufAvailable(ctx: ?*anyopaque) callconv(.c) u64 {
        const self: *BufferStorage = @ptrCast(@alignCast(ctx orelse return 0));
        return @intCast(self.data.items.len);
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "noop storage write returns ok" {
    try std.testing.expectEqual(@as(c_int, 0), noop_storage.write("test"));
}

test "noop storage read returns 0" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqual(@as(u32, 0), noop_storage.read(&buf));
}

test "noop storage available returns 0" {
    try std.testing.expectEqual(@as(u64, 0), noop_storage.availableBytes());
}

test "buffer storage write/read round-trip" {
    var bs = BufferStorage.init(std.testing.allocator);
    defer bs.deinit();

    const vt = bs.vtable();
    _ = vt.write("hello world");

    var buf: [64]u8 = undefined;
    const n = vt.read(&buf);
    try std.testing.expectEqualStrings("hello world", buf[0..n]);
}

test "buffer storage discard_oldest" {
    var bs = BufferStorage.init(std.testing.allocator);
    defer bs.deinit();

    const vt = bs.vtable();
    _ = vt.write("abcdef");
    vt.discardOldest(3);
    try std.testing.expectEqual(@as(u64, 3), vt.availableBytes());

    var buf: [64]u8 = undefined;
    const n = vt.read(&buf);
    try std.testing.expectEqualStrings("def", buf[0..n]);
}
