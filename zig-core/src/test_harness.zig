// Terra Zig Core — test_harness.zig
// Test utilities: createTestInstance, drainSpans, reset.

const std = @import("std");
const terra_mod = @import("terra.zig");
const models = @import("models.zig");
const config_mod = @import("config.zig");
const clock = @import("clock.zig");

const TerraInstance = terra_mod.TerraInstance;
const TerraConfig = config_mod.TerraConfig;
const SpanRecord = models.SpanRecord;

pub const TestConfig = struct {
    max_spans: u32 = 64,
    clock_fn: ?clock.ClockFn = null,
    clock_ctx: ?*anyopaque = null,
};

/// Create a fresh test instance with testing.allocator (leak detection).
pub fn createTestInstance(allocator: std.mem.Allocator, overrides: ?TestConfig) !*TerraInstance {
    var cfg = TerraConfig.default();
    cfg.allocator = allocator;

    if (overrides) |ov| {
        cfg.max_spans = ov.max_spans;
        // Ensure batch_size does not exceed max_spans
        if (cfg.batch_size > ov.max_spans) {
            cfg.batch_size = ov.max_spans;
        }
        if (ov.clock_fn) |cfn| {
            cfg.clock_fn = cfn;
            cfg.clock_ctx = ov.clock_ctx;
        }
    }

    return TerraInstance.create(allocator, cfg);
}

/// Destroy test instance and check for leaks.
pub fn destroyTestInstance(inst: *TerraInstance) void {
    const allocator = inst.allocator;
    inst.destroy();
    _ = allocator;
}

/// Drain completed spans into caller-provided buffer. Returns count.
pub fn drainSpans(inst: *TerraInstance, buf: []SpanRecord) u32 {
    return inst.drainSpans(buf);
}

/// Reset all state: ring buffer, metrics, session.
pub fn resetInstance(inst: *TerraInstance) void {
    inst.reset();
}

// ── Tests ───────────────────────────────────────────────────────────────
test "test harness create and destroy" {
    const inst = try createTestInstance(std.testing.allocator, null);
    destroyTestInstance(inst);
}

test "test harness with custom clock" {
    var clk = clock.TestingClock{ .current_ns = 42_000 };
    const inst = try createTestInstance(std.testing.allocator, .{
        .clock_fn = clock.TestingClock.read,
        .clock_ctx = clk.context(),
    });
    defer destroyTestInstance(inst);
    _ = &clk;
}

test "test harness drain returns 0 when empty" {
    const inst = try createTestInstance(std.testing.allocator, null);
    defer destroyTestInstance(inst);

    var buf: [8]SpanRecord = undefined;
    const count = drainSpans(inst, &buf);
    try std.testing.expectEqual(@as(u32, 0), count);
}
