// Terra Zig Core — clock.zig
// Clock abstraction: ClockFn, std_clock, testing_clock

const std = @import("std");

// ── ClockFn ─────────────────────────────────────────────────────────────
// Returns nanoseconds since epoch. Context pointer allows custom state.
pub const ClockFn = *const fn (ctx: ?*anyopaque) callconv(.c) u64;

// ── std_clock ───────────────────────────────────────────────────────────
// Uses std.time.nanoTimestamp() — monotonic on supported platforms.
pub fn stdClock(_: ?*anyopaque) callconv(.c) u64 {
    return @intCast(std.time.nanoTimestamp());
}

// ── TestingClock ────────────────────────────────────────────────────────
// Manually advanceable clock for deterministic tests.
pub const TestingClock = struct {
    current_ns: u64 = 0,

    pub fn advance(self: *TestingClock, ns: u64) void {
        self.current_ns += ns;
    }

    pub fn setTime(self: *TestingClock, ns: u64) void {
        self.current_ns = ns;
    }

    pub fn read(ctx: ?*anyopaque) callconv(.c) u64 {
        const self: *TestingClock = @ptrCast(@alignCast(ctx.?));
        return self.current_ns;
    }

    pub fn clockFn(self: *TestingClock) ClockFn {
        _ = self;
        return read;
    }

    pub fn context(self: *TestingClock) ?*anyopaque {
        return @ptrCast(self);
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "stdClock returns non-zero" {
    const t = stdClock(null);
    try std.testing.expect(t > 0);
}

test "stdClock monotonicity" {
    const t1 = stdClock(null);
    const t2 = stdClock(null);
    try std.testing.expect(t2 >= t1);
}

test "TestingClock advance" {
    var clk = TestingClock{ .current_ns = 1000 };
    try std.testing.expectEqual(@as(u64, 1000), TestingClock.read(clk.context()));

    clk.advance(500);
    try std.testing.expectEqual(@as(u64, 1500), TestingClock.read(clk.context()));
}

test "TestingClock setTime" {
    var clk = TestingClock{};
    clk.setTime(999_999);
    try std.testing.expectEqual(@as(u64, 999_999), TestingClock.read(clk.context()));
}

test "TestingClock stall simulation" {
    var clk = TestingClock{ .current_ns = 0 };
    const t1 = TestingClock.read(clk.context());
    // No advance = stall
    const t2 = TestingClock.read(clk.context());
    try std.testing.expectEqual(t1, t2);
    // Now advance past stall threshold (300ms = 300_000_000 ns)
    clk.advance(300_000_001);
    const t3 = TestingClock.read(clk.context());
    try std.testing.expect(t3 - t1 > 300_000_000);
}
