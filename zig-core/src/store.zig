// Terra Zig Core — store.zig
// Ring buffer of pre-allocated Span slots with LRU eviction.

const std = @import("std");
const span_mod = @import("span.zig");
const models = @import("models.zig");

const Span = span_mod.Span;
const SpanRecord = models.SpanRecord;

// ── SpanStore ───────────────────────────────────────────────────────────
pub const SpanStore = struct {
    slots: []Span,
    capacity: u32,
    allocator: std.mem.Allocator,
    // Ring buffer tracking
    head: u32 = 0, // Next slot to write
    count: u32 = 0, // Number of active spans
    completed_count: u32 = 0,
    eviction_count: u64 = 0,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, capacity: u32) !SpanStore {
        const slots = try allocator.alloc(Span, capacity);
        @memset(slots, Span{});
        return .{
            .slots = slots,
            .capacity = capacity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SpanStore) void {
        self.allocator.free(self.slots);
    }

    /// Allocate a span slot. Returns null if at capacity and no evictable span.
    pub fn allocateSpan(self: *SpanStore) ?*Span {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count < self.capacity) {
            // Find first inactive slot
            var i: u32 = 0;
            while (i < self.capacity) : (i += 1) {
                if (!self.slots[i].active and self.slots[i].end_time_ns == 0) {
                    self.slots[i] = Span{};
                    self.slots[i].active = true;
                    self.count += 1;
                    return &self.slots[i];
                }
            }
            // All active — try to evict oldest completed
            return self.evictAndAllocate();
        }

        return self.evictAndAllocate();
    }

    fn evictAndAllocate(self: *SpanStore) ?*Span {
        // Find oldest completed (ended) span for eviction
        var oldest_idx: ?u32 = null;
        var oldest_time: u64 = std.math.maxInt(u64);

        var i: u32 = 0;
        while (i < self.capacity) : (i += 1) {
            if (self.slots[i].ended and self.slots[i].end_time_ns < oldest_time) {
                oldest_time = self.slots[i].end_time_ns;
                oldest_idx = i;
            }
        }

        if (oldest_idx) |idx| {
            self.eviction_count += 1;
            self.slots[idx] = Span{};
            self.slots[idx].active = true;
            return &self.slots[idx];
        }

        return null; // All slots active and not ended
    }

    /// Mark a span as completed.
    pub fn completeSpan(self: *SpanStore, s: *Span) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (!s.ended) return;
        self.completed_count += 1;
    }

    /// Deep-copy completed span data into batch buffer. Returns count drained.
    pub fn drainCompleted(self: *SpanStore, batch: []SpanRecord, max: u32) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var drained: u32 = 0;
        var i: u32 = 0;
        while (i < self.capacity and drained < max) : (i += 1) {
            if (self.slots[i].ended) {
                batch[drained] = self.slots[i].toRecord();
                // Mark slot as reusable
                self.slots[i] = Span{};
                self.count -|= 1;
                drained += 1;
            }
        }
        return drained;
    }

    /// Reset all state.
    pub fn reset(self: *SpanStore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        @memset(self.slots, Span{});
        self.head = 0;
        self.count = 0;
        self.completed_count = 0;
        self.eviction_count = 0;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
const clock = @import("clock.zig");

test "SpanStore init and deinit" {
    var store = try SpanStore.init(std.testing.allocator, 16);
    defer store.deinit();
    try std.testing.expectEqual(@as(u32, 0), store.count);
}

test "SpanStore allocate span" {
    var store = try SpanStore.init(std.testing.allocator, 4);
    defer store.deinit();

    const s = store.allocateSpan();
    try std.testing.expect(s != null);
    try std.testing.expectEqual(@as(u32, 1), store.count);
}

test "SpanStore capacity limits" {
    var store = try SpanStore.init(std.testing.allocator, 2);
    defer store.deinit();

    var clk = clock.TestingClock{ .current_ns = 100 };

    // Fill both slots
    const s1 = store.allocateSpan().?;
    s1.* = span_mod.Span.init("s1", models.TraceID.generate(), models.SpanID.zero, clock.TestingClock.read, clk.context(), .never, false);

    const s2 = store.allocateSpan().?;
    s2.* = span_mod.Span.init("s2", models.TraceID.generate(), models.SpanID.zero, clock.TestingClock.read, clk.context(), .never, false);

    // No completed spans, can't allocate
    const s3 = store.allocateSpan();
    try std.testing.expect(s3 == null);

    // End s1, now eviction should work
    clk.advance(100);
    s1.end();
    const s4 = store.allocateSpan();
    try std.testing.expect(s4 != null);
}

test "SpanStore drainCompleted deep-copies" {
    var store = try SpanStore.init(std.testing.allocator, 4);
    defer store.deinit();

    var clk = clock.TestingClock{ .current_ns = 1000 };

    const s = store.allocateSpan().?;
    s.* = span_mod.Span.init("gen_ai.inference", models.TraceID{ .hi = 1, .lo = 2 }, models.SpanID.zero, clock.TestingClock.read, clk.context(), .never, false);
    s.setString("model", "gpt-4");
    clk.advance(500);
    s.end();
    store.completeSpan(s);

    var batch: [4]SpanRecord = undefined;
    const drained = store.drainCompleted(&batch, 4);
    try std.testing.expectEqual(@as(u32, 1), drained);
    try std.testing.expectEqualStrings("gen_ai.inference", batch[0].nameSlice());
}

test "SpanStore eviction order" {
    var store = try SpanStore.init(std.testing.allocator, 2);
    defer store.deinit();

    var clk = clock.TestingClock{ .current_ns = 100 };

    // Fill and end both
    const s1 = store.allocateSpan().?;
    s1.* = span_mod.Span.init("first", models.TraceID.generate(), models.SpanID.zero, clock.TestingClock.read, clk.context(), .never, false);
    clk.advance(10);
    s1.end();

    clk.advance(10);
    const s2 = store.allocateSpan().?;
    s2.* = span_mod.Span.init("second", models.TraceID.generate(), models.SpanID.zero, clock.TestingClock.read, clk.context(), .never, false);
    clk.advance(10);
    s2.end();

    // Next alloc should evict oldest (s1, end_time=110)
    const s3 = store.allocateSpan().?;
    _ = s3;
    try std.testing.expect(store.eviction_count > 0);
}

test "SpanStore reset" {
    var store = try SpanStore.init(std.testing.allocator, 4);
    defer store.deinit();

    _ = store.allocateSpan();
    _ = store.allocateSpan();
    store.reset();

    try std.testing.expectEqual(@as(u32, 0), store.count);
    try std.testing.expectEqual(@as(u32, 0), store.completed_count);
}
