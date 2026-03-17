// Terra Zig Core — shm_transport.zig
// Lock-free ring buffer for inter-process span transfer via shared memory.
//
// Architecture:
// ┌─────────────────────────────────────────────────────────────┐
// │ SharedRingBuffer (mapped into shared memory by the host)    │
// │                                                             │
// │  ┌─────────┬─────────┬──────────┬─────────────────────────┐ │
// │  │ head(8) │ tail(8) │ cap(4)   │ data[capacity]          │ │
// │  └─────────┴─────────┴──────────┴─────────────────────────┘ │
// │                                                             │
// │  Producer (Terra SDK):  writes at tail, advances tail       │
// │  Consumer (collector):  reads from head, advances head      │
// │                                                             │
// │  Entry format: [len: u32][payload: len bytes][pad to align] │
// └─────────────────────────────────────────────────────────────┘
//
// The actual shared memory mapping (mmap/shmget) is platform-specific
// and deferred. This module provides the data structure and TransportVTable
// interface operating on a caller-provided buffer.

const std = @import("std");
const transport = @import("transport.zig");

// ── Entry header ────────────────────────────────────────────────────────
const ENTRY_ALIGNMENT = 8;
const ENTRY_HEADER_SIZE = 4; // u32 length prefix

fn alignUp(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

// ── SharedRingBuffer ────────────────────────────────────────────────────
/// Lock-free SPSC (single-producer, single-consumer) ring buffer.
/// Producer writes span data at tail; consumer reads from head.
/// Atomic head/tail ensure cache-line-safe coordination without locks.
pub const SharedRingBuffer = struct {
    /// Points to the start of the data region.
    data: [*]u8,
    /// Total capacity of the data region in bytes.
    capacity: u32,
    /// Atomic write cursor (producer owns). Byte offset into data[].
    tail: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    /// Atomic read cursor (consumer owns). Byte offset into data[].
    head: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    /// Monotonic counters for diagnostics (atomic for thread-safe access).
    entries_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    entries_dropped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Initialize a ring buffer over a caller-provided byte region.
    /// The caller must ensure `buf` remains valid and is not freed while the ring is in use.
    pub fn init(buf: []u8) SharedRingBuffer {
        return .{
            .data = buf.ptr,
            .capacity = @intCast(buf.len),
        };
    }

    /// Available bytes for writing (approximate — safe for SPSC).
    pub fn availableWrite(self: *const SharedRingBuffer) u32 {
        const h = self.head.load(.acquire);
        const t = self.tail.load(.monotonic);
        if (t >= h) {
            // Available = capacity - (tail - head) - 1 (to distinguish full from empty)
            return self.capacity - (t - h) - 1;
        } else {
            return h - t - 1;
        }
    }

    /// Available bytes for reading (approximate — safe for SPSC).
    pub fn availableRead(self: *const SharedRingBuffer) u32 {
        const h = self.head.load(.monotonic);
        const t = self.tail.load(.acquire);
        if (t >= h) {
            return t - h;
        } else {
            return self.capacity - h + t;
        }
    }

    /// Write an entry (length-prefixed) into the ring buffer.
    /// Returns true if the entry was written, false if not enough space.
    pub fn write(self: *SharedRingBuffer, payload: []const u8) bool {
        const entry_size = alignUp(ENTRY_HEADER_SIZE + payload.len, ENTRY_ALIGNMENT);
        if (entry_size > self.capacity / 2) {
            // Entry too large for this ring
            _ = self.entries_dropped.fetchAdd(1, .monotonic);
            return false;
        }

        if (self.availableWrite() < entry_size) {
            _ = self.entries_dropped.fetchAdd(1, .monotonic);
            return false;
        }

        const t = self.tail.load(.monotonic);

        // Write length header
        self.writeAt(t, std.mem.asBytes(&@as(u32, @intCast(payload.len))));

        // Write payload
        self.writeAt(t + ENTRY_HEADER_SIZE, payload);

        // Zero padding
        const pad_start = ENTRY_HEADER_SIZE + payload.len;
        const pad_len = entry_size - pad_start;
        if (pad_len > 0) {
            var i: usize = 0;
            while (i < pad_len) : (i += 1) {
                const off = (t + pad_start + i) % self.capacity;
                self.data[off] = 0;
            }
        }

        // Advance tail (release so consumer sees the write)
        const new_tail = (t + @as(u32, @intCast(entry_size))) % self.capacity;
        self.tail.store(new_tail, .release);
        _ = self.entries_written.fetchAdd(1, .monotonic);
        return true;
    }

    /// Read the next entry from the ring buffer into `out_buf`.
    /// Returns the payload slice within out_buf, or null if empty.
    pub fn read(self: *SharedRingBuffer, out_buf: []u8) ?[]const u8 {
        if (self.availableRead() < ENTRY_HEADER_SIZE) return null;

        const h = self.head.load(.monotonic);

        // Read length header
        var len_bytes: [4]u8 = undefined;
        self.readAt(h, &len_bytes);
        const payload_len = std.mem.readInt(u32, &len_bytes, .little);

        if (payload_len == 0 or payload_len > out_buf.len) return null;

        const entry_size = alignUp(ENTRY_HEADER_SIZE + payload_len, ENTRY_ALIGNMENT);
        if (self.availableRead() < entry_size) return null;

        // Read payload
        self.readAt(h + ENTRY_HEADER_SIZE, out_buf[0..payload_len]);

        // Advance head (release so producer sees the read)
        const new_head = (h + @as(u32, @intCast(entry_size))) % self.capacity;
        self.head.store(new_head, .release);

        return out_buf[0..payload_len];
    }

    /// Reset ring to empty state. NOT thread-safe — call only when no readers/writers.
    pub fn reset(self: *SharedRingBuffer) void {
        self.head.store(0, .monotonic);
        self.tail.store(0, .monotonic);
        self.entries_written.store(0, .monotonic);
        self.entries_dropped.store(0, .monotonic);
    }

    // ── Internal helpers ────────────────────────────────────────────────

    fn writeAt(self: *SharedRingBuffer, offset: u32, payload: []const u8) void {
        for (payload, 0..) |b, i| {
            const off = (offset + @as(u32, @intCast(i))) % self.capacity;
            self.data[off] = b;
        }
    }

    fn readAt(self: *const SharedRingBuffer, offset: u32, out: []u8) void {
        for (out, 0..) |*b, i| {
            const off = (offset + @as(u32, @intCast(i))) % self.capacity;
            b.* = self.data[off];
        }
    }
};

// ── TransportVTable implementation ──────────────────────────────────────
fn shmSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const ring: *SharedRingBuffer = @ptrCast(@alignCast(ctx orelse return -1));
    if (ring.write(data[0..len])) {
        return 0;
    }
    return -1;
}

fn shmFlush(_: ?*anyopaque) callconv(.c) void {
    // Ring buffer is always "flushed" — entries are available immediately.
}

fn shmShutdown(_: ?*anyopaque) callconv(.c) void {
    // The shared memory region is owned by the caller — we don't unmap here.
}

/// Create a TransportVTable backed by a SharedRingBuffer.
pub fn vtable(ring: *SharedRingBuffer) transport.TransportVTable {
    return .{
        .send_fn = shmSend,
        .flush_fn = shmFlush,
        .shutdown_fn = shmShutdown,
        .context = @ptrCast(ring),
    };
}

// ── Tests ───────────────────────────────────────────────────────────────
test "SharedRingBuffer init" {
    var buf: [256]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);
    try std.testing.expectEqual(@as(u32, 256), ring.capacity);
    try std.testing.expectEqual(@as(u32, 0), ring.head.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), ring.tail.load(.monotonic));
}

test "SharedRingBuffer write and read round-trip" {
    var buf: [1024]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    const payload = "hello-terra";
    try std.testing.expect(ring.write(payload));
    try std.testing.expectEqual(@as(u64, 1), ring.entries_written.load(.monotonic));

    var out: [128]u8 = undefined;
    const result = ring.read(&out);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello-terra", result.?);
}

test "SharedRingBuffer multiple entries" {
    var buf: [1024]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    try std.testing.expect(ring.write("first"));
    try std.testing.expect(ring.write("second"));
    try std.testing.expect(ring.write("third"));
    try std.testing.expectEqual(@as(u64, 3), ring.entries_written.load(.monotonic));

    var out: [128]u8 = undefined;
    const r1 = ring.read(&out);
    try std.testing.expect(r1 != null);
    try std.testing.expectEqualStrings("first", r1.?);

    const r2 = ring.read(&out);
    try std.testing.expect(r2 != null);
    try std.testing.expectEqualStrings("second", r2.?);

    const r3 = ring.read(&out);
    try std.testing.expect(r3 != null);
    try std.testing.expectEqualStrings("third", r3.?);
}

test "SharedRingBuffer read empty returns null" {
    var buf: [256]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    var out: [128]u8 = undefined;
    const result = ring.read(&out);
    try std.testing.expect(result == null);
}

test "SharedRingBuffer drop when full" {
    var buf: [64]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    // Fill the ring
    const big_payload = "a" ** 28; // 28 bytes payload + 4 header = 32, aligned to 32
    try std.testing.expect(ring.write(big_payload));

    // This should fail — not enough space
    try std.testing.expect(!ring.write(big_payload));
    try std.testing.expectEqual(@as(u64, 1), ring.entries_dropped.load(.monotonic));
}

test "SharedRingBuffer reset" {
    var buf: [256]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    _ = ring.write("data");
    ring.reset();

    try std.testing.expectEqual(@as(u32, 0), ring.head.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 0), ring.tail.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), ring.entries_written.load(.monotonic));
}

test "SharedRingBuffer vtable integration" {
    var buf: [1024]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);
    const vt = vtable(&ring);

    const result = vt.send("test-span-data");
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqual(@as(u64, 1), ring.entries_written.load(.monotonic));

    // Read back via ring directly
    var out: [128]u8 = undefined;
    const read_result = ring.read(&out);
    try std.testing.expect(read_result != null);
    try std.testing.expectEqualStrings("test-span-data", read_result.?);
}

test "SharedRingBuffer entry too large" {
    var buf: [64]u8 = undefined;
    var ring = SharedRingBuffer.init(&buf);

    // Entry larger than half capacity should be rejected
    const huge = "x" ** 40;
    try std.testing.expect(!ring.write(huge));
    try std.testing.expectEqual(@as(u64, 1), ring.entries_dropped.load(.monotonic));
}
