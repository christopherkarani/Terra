// Terra Zig Core — file_storage.zig
// File-based offline buffering for OTLP batches.
//
// Writes OTLP batches to individual files in a configurable directory.
// Filenames: terra_<timestamp_ns>.otlp
// Implements the StorageVTable interface for seamless integration.
//
// NOT available on freestanding targets (no filesystem).

const std = @import("std");
const build_options = @import("build_options");
const storage = @import("storage.zig");

/// File storage is only available when std is present (not freestanding/no_std).
pub const is_available = !build_options.TERRA_NO_STD;

// ── FileStorage ───────────────────────────────────────────────────────────
pub const FileStorage = struct {
    allocator: std.mem.Allocator,
    /// Directory path for storing OTLP batch files.
    dir_path: []const u8,
    /// Maximum total bytes allowed in the directory before discard_oldest kicks in.
    max_bytes: u64 = 10 * 1024 * 1024, // 10 MiB default
    /// Number of writes performed.
    write_count: u64 = 0,
    /// Number of files discarded.
    discard_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, dir_path: []const u8) FileStorage {
        return .{
            .allocator = allocator,
            .dir_path = dir_path,
        };
    }

    /// Write an OTLP batch to a new file.
    /// Filename: terra_<timestamp_ns>.otlp
    /// On freestanding builds, this is a no-op stub.
    pub fn writeFile(self: *FileStorage, data: []const u8) !void {
        return self.writeFileInner(data, false);
    }

    fn writeFileInner(self: *FileStorage, data: []const u8, retried: bool) !void {
        if (comptime !is_available) return;

        // Ensure directory exists
        var dir = std.fs.cwd().openDir(self.dir_path, .{}) catch |err| {
            if (err == error.FileNotFound and !retried) {
                std.fs.cwd().makePath(self.dir_path) catch return err;
                return self.writeFileInner(data, true); // single retry
            }
            return err;
        };
        defer dir.close();

        // Generate filename with nanosecond timestamp
        var name_buf: [64]u8 = undefined;
        const timestamp = @as(u64, @intCast(std.time.nanoTimestamp()));
        const name = std.fmt.bufPrint(&name_buf, "terra_{d}.otlp", .{timestamp}) catch return error.NameTooLong;

        // Write atomically: write to file, then close
        const file = dir.createFile(name, .{}) catch return error.FileCreationFailed;
        defer file.close();
        file.writeAll(data) catch return error.WriteFailed;

        self.write_count += 1;
    }

    /// Scan the directory and return total size of all .otlp files.
    pub fn scanTotalSize(self: *const FileStorage) u64 {
        if (comptime !is_available) return 0;

        const dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch return 0;
        // We need a mutable copy for the iterator since close modifies state
        var dir_mut = dir;
        defer dir_mut.close();

        var total: u64 = 0;
        var iter = dir_mut.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".otlp")) continue;
            if (!std.mem.startsWith(u8, entry.name, "terra_")) continue;

            const stat = dir_mut.statFile(entry.name) catch continue;
            total += stat.size;
        }
        return total;
    }

    /// Delete the oldest .otlp files until at least `bytes` have been freed.
    pub fn discardOldestFiles(self: *FileStorage, bytes: u64) void {
        if (comptime !is_available) return;

        var dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        // Collect file names and sizes — we need to sort by name (which encodes timestamp)
        var files: std.ArrayList(FileEntry) = .empty;
        defer {
            for (files.items) |f| self.allocator.free(f.name);
            files.deinit(self.allocator);
        }

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".otlp")) continue;
            if (!std.mem.startsWith(u8, entry.name, "terra_")) continue;

            const stat = dir.statFile(entry.name) catch continue;
            const name_copy = self.allocator.dupe(u8, entry.name) catch continue;
            files.append(self.allocator, .{ .name = name_copy, .size = stat.size }) catch {
                self.allocator.free(name_copy);
                continue;
            };
        }

        // Sort by name ascending (oldest first, since filenames encode timestamp)
        std.mem.sort(FileEntry, files.items, {}, struct {
            fn lessThan(_: void, a: FileEntry, b: FileEntry) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.lessThan);

        // Delete oldest until we've freed enough
        var freed: u64 = 0;
        for (files.items) |f| {
            if (freed >= bytes) break;
            dir.deleteFile(f.name) catch continue;
            freed += f.size;
            self.discard_count += 1;
        }
    }

    /// Create a StorageVTable backed by this FileStorage.
    pub fn vtable(self: *FileStorage) storage.StorageVTable {
        return .{
            .write_fn = fileStorageWrite,
            .read_fn = fileStorageRead,
            .discard_oldest_fn = fileStorageDiscard,
            .available_bytes_fn = fileStorageAvailable,
            .context = @ptrCast(self),
        };
    }
};

const FileEntry = struct {
    name: []u8,
    size: u64,
};

// ── StorageVTable callbacks ───────────────────────────────────────────────
fn fileStorageWrite(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const self: *FileStorage = @ptrCast(@alignCast(ctx orelse return -1));
    self.writeFile(data[0..len]) catch return -1;
    return 0;
}

fn fileStorageRead(buf: [*]u8, max_len: u32, ctx: ?*anyopaque) callconv(.c) u32 {
    if (comptime !is_available) return 0;
    const self: *FileStorage = @ptrCast(@alignCast(ctx orelse return 0));

    // Read the oldest file (first alphabetically = oldest timestamp)
    var dir = std.fs.cwd().openDir(self.dir_path, .{ .iterate = true }) catch return 0;
    defer dir.close();

    var oldest_name: ?[64]u8 = null;
    var oldest_len: usize = 0;

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".otlp")) continue;
        if (!std.mem.startsWith(u8, entry.name, "terra_")) continue;

        if (oldest_name == null or std.mem.order(u8, entry.name, oldest_name.?[0..oldest_len]) == .lt) {
            if (entry.name.len <= 64) {
                var name: [64]u8 = undefined;
                @memcpy(name[0..entry.name.len], entry.name);
                oldest_name = name;
                oldest_len = entry.name.len;
            }
        }
    }

    if (oldest_name == null) return 0;

    const file = dir.openFile(oldest_name.?[0..oldest_len], .{}) catch return 0;
    defer file.close();

    const bytes_read = file.read(buf[0..max_len]) catch return 0;
    return @intCast(bytes_read);
}

fn fileStorageDiscard(bytes: u32, ctx: ?*anyopaque) callconv(.c) void {
    const self: *FileStorage = @ptrCast(@alignCast(ctx orelse return));
    self.discardOldestFiles(@intCast(bytes));
}

fn fileStorageAvailable(ctx: ?*anyopaque) callconv(.c) u64 {
    const self: *const FileStorage = @ptrCast(@alignCast(ctx orelse return 0));
    return self.scanTotalSize();
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "FileStorage init" {
    const fs = FileStorage.init(std.testing.allocator, "/tmp/terra_test");
    try std.testing.expectEqual(@as(u64, 0), fs.write_count);
    try std.testing.expectEqual(@as(u64, 0), fs.discard_count);
    try std.testing.expectEqual(@as(u64, 10 * 1024 * 1024), fs.max_bytes);
}

test "FileStorage write and scan" {
    const dir_path = "/tmp/terra_file_storage_test";

    // Clean up from previous runs
    std.fs.cwd().deleteTree(dir_path) catch {};
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    var fs = FileStorage.init(std.testing.allocator, dir_path);

    // Write a batch
    try fs.writeFile("otlp-batch-1");
    try std.testing.expectEqual(@as(u64, 1), fs.write_count);

    // Scan should find data
    const total = fs.scanTotalSize();
    try std.testing.expectEqual(@as(u64, 12), total); // "otlp-batch-1" = 12 bytes
}

test "FileStorage write and read via vtable" {
    const dir_path = "/tmp/terra_file_storage_vtable_test";

    std.fs.cwd().deleteTree(dir_path) catch {};
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    var fs = FileStorage.init(std.testing.allocator, dir_path);
    const vt = fs.vtable();

    // Write via vtable
    const write_result = vt.write("hello-otlp");
    try std.testing.expectEqual(@as(c_int, 0), write_result);

    // Available bytes should reflect the write
    const avail = vt.availableBytes();
    try std.testing.expectEqual(@as(u64, 10), avail); // "hello-otlp" = 10 bytes

    // Read via vtable
    var buf: [64]u8 = undefined;
    const n = vt.read(&buf);
    try std.testing.expectEqual(@as(u32, 10), n);
    try std.testing.expectEqualStrings("hello-otlp", buf[0..n]);
}

test "FileStorage discard oldest" {
    const dir_path = "/tmp/terra_file_storage_discard_test";

    std.fs.cwd().deleteTree(dir_path) catch {};
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    var fs = FileStorage.init(std.testing.allocator, dir_path);

    // Write multiple batches with slight delay to get different timestamps
    try fs.writeFile("batch-aaa");
    // Force different timestamp by sleeping briefly
    std.Thread.sleep(1_000_000); // 1ms
    try fs.writeFile("batch-bbb");
    try std.testing.expectEqual(@as(u64, 2), fs.write_count);

    // Discard enough bytes to remove at least one file
    fs.discardOldestFiles(9); // "batch-aaa" = 9 bytes

    // Should have discarded one file
    try std.testing.expect(fs.discard_count >= 1);

    // Remaining should be approximately one file's worth
    const remaining = fs.scanTotalSize();
    try std.testing.expect(remaining <= 9); // at most one file left
}

test "FileStorage vtable discard" {
    const dir_path = "/tmp/terra_file_storage_vt_discard_test";

    std.fs.cwd().deleteTree(dir_path) catch {};
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    var fs = FileStorage.init(std.testing.allocator, dir_path);
    const vt = fs.vtable();

    _ = vt.write("data-1234");
    vt.discardOldest(100); // discard all

    const avail = vt.availableBytes();
    try std.testing.expectEqual(@as(u64, 0), avail);
}

test "FileStorage scan empty directory" {
    const dir_path = "/tmp/terra_file_storage_empty_test";

    std.fs.cwd().deleteTree(dir_path) catch {};
    std.fs.cwd().makePath(dir_path) catch {};
    defer std.fs.cwd().deleteTree(dir_path) catch {};

    const fs = FileStorage.init(std.testing.allocator, dir_path);
    const total = fs.scanTotalSize();
    try std.testing.expectEqual(@as(u64, 0), total);
}

test "FileStorage scan nonexistent directory" {
    const fs = FileStorage.init(std.testing.allocator, "/tmp/terra_nonexistent_dir_99999");
    const total = fs.scanTotalSize();
    try std.testing.expectEqual(@as(u64, 0), total);
}
