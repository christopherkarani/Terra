// Terra Zig Core — metrics.zig
// Counter, Histogram (thread-safe), TerraMetrics.

const std = @import("std");
const build_options = @import("build_options");

// ── Counter ─────────────────────────────────────────────────────────────
// Lock-free via atomics.
pub const Counter = struct {
    value: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    pub fn increment(self: *Counter) void {
        _ = self.value.fetchAdd(1, .monotonic);
    }

    pub fn add(self: *Counter, delta: i64) void {
        _ = self.value.fetchAdd(delta, .monotonic);
    }

    pub fn get(self: *const Counter) i64 {
        return self.value.load(.monotonic);
    }

    pub fn reset(self: *Counter) void {
        self.value.store(0, .monotonic);
    }
};

// ── Histogram ───────────────────────────────────────────────────────────
// Mutex-protected for f64 operations.
pub const Histogram = struct {
    sum: f64 = 0,
    count: u64 = 0,
    min: f64 = std.math.floatMax(f64),
    max: f64 = -std.math.floatMax(f64),
    mutex: std.Thread.Mutex = .{},

    pub fn record(self: *Histogram, value: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.sum += value;
        self.count += 1;
        if (value < self.min) self.min = value;
        if (value > self.max) self.max = value;
    }

    pub fn getSum(self: *Histogram) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.sum;
    }

    pub fn getCount(self: *Histogram) u64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    pub fn getMean(self: *Histogram) f64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.count == 0) return 0;
        return self.sum / @as(f64, @floatFromInt(self.count));
    }

    pub fn reset(self: *Histogram) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.sum = 0;
        self.count = 0;
        self.min = std.math.floatMax(f64);
        self.max = -std.math.floatMax(f64);
    }
};

// ── TerraMetrics ────────────────────────────────────────────────────────
pub const TerraMetrics = struct {
    inference_count: Counter = .{},
    spans_created: Counter = .{},
    spans_dropped: Counter = .{},
    transport_errors: Counter = .{},
    inference_duration_ms: Histogram = .{},
    input_tokens_total: Counter = .{},
    output_tokens_total: Counter = .{},

    pub fn reset(self: *TerraMetrics) void {
        self.inference_count.reset();
        self.spans_created.reset();
        self.spans_dropped.reset();
        self.transport_errors.reset();
        self.inference_duration_ms.reset();
        self.input_tokens_total.reset();
        self.output_tokens_total.reset();
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "Counter increment and get" {
    var c = Counter{};
    c.increment();
    c.increment();
    c.increment();
    try std.testing.expectEqual(@as(i64, 3), c.get());
}

test "Counter add" {
    var c = Counter{};
    c.add(10);
    c.add(5);
    try std.testing.expectEqual(@as(i64, 15), c.get());
}

test "Counter reset" {
    var c = Counter{};
    c.add(42);
    c.reset();
    try std.testing.expectEqual(@as(i64, 0), c.get());
}

test "Histogram record and getters" {
    var h = Histogram{};
    h.record(10.0);
    h.record(20.0);
    h.record(30.0);

    try std.testing.expectEqual(@as(u64, 3), h.getCount());
    try std.testing.expectApproxEqAbs(@as(f64, 60.0), h.getSum(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), h.getMean(), 0.001);
}

test "Histogram reset" {
    var h = Histogram{};
    h.record(100.0);
    h.reset();
    try std.testing.expectEqual(@as(u64, 0), h.getCount());
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), h.getSum(), 0.001);
}

test "TerraMetrics reset" {
    var m = TerraMetrics{};
    m.inference_count.add(10);
    m.spans_created.add(20);
    m.reset();
    try std.testing.expectEqual(@as(i64, 0), m.inference_count.get());
    try std.testing.expectEqual(@as(i64, 0), m.spans_created.get());
}

test "Counter concurrent increment" {
    var c = Counter{};
    const threads = 8;
    const per_thread = 10_000;

    var handles: [threads]std.Thread = undefined;
    for (&handles) |*h| {
        h.* = std.Thread.spawn(.{}, struct {
            fn run(counter: *Counter) void {
                var i: usize = 0;
                while (i < per_thread) : (i += 1) {
                    counter.increment();
                }
            }
        }.run, .{&c}) catch unreachable;
    }
    for (&handles) |*h| h.join();

    try std.testing.expectEqual(@as(i64, threads * per_thread), c.get());
}
