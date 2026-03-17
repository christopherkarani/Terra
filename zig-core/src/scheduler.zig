// Terra Zig Core — scheduler.zig
// SchedulerVTable, std_scheduler, noop_scheduler.

const std = @import("std");

pub const ScheduleFn = *const fn (callback: *const fn (?*anyopaque) callconv(.c) void, interval_ms: u64, cb_ctx: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) u64;
pub const CancelFn = *const fn (handle: u64, ctx: ?*anyopaque) callconv(.c) void;

pub const SchedulerVTable = struct {
    schedule_fn: ScheduleFn,
    cancel_fn: CancelFn,
    context: ?*anyopaque = null,

    pub fn schedule(self: SchedulerVTable, callback: *const fn (?*anyopaque) callconv(.c) void, interval_ms: u64, cb_ctx: ?*anyopaque) u64 {
        return self.schedule_fn(callback, interval_ms, cb_ctx, self.context);
    }

    pub fn cancel(self: SchedulerVTable, handle: u64) void {
        self.cancel_fn(handle, self.context);
    }
};

// ── Noop Scheduler ──────────────────────────────────────────────────────
fn noopSchedule(_: *const fn (?*anyopaque) callconv(.c) void, _: u64, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) u64 {
    return 0;
}

fn noopCancel(_: u64, _: ?*anyopaque) callconv(.c) void {}

pub const noop_scheduler = SchedulerVTable{
    .schedule_fn = noopSchedule,
    .cancel_fn = noopCancel,
    .context = null,
};

// ── Std Scheduler ───────────────────────────────────────────────────────
// Single background thread that fires callbacks at intervals.
pub const StdScheduler = struct {
    const Entry = struct {
        callback: *const fn (?*anyopaque) callconv(.c) void,
        interval_ns: u64,
        cb_ctx: ?*anyopaque,
        last_fire_ns: u64,
        active: bool,
        handle: u64,
    };

    entries: [16]Entry = [_]Entry{.{
        .callback = undefined,
        .interval_ns = 0,
        .cb_ctx = null,
        .last_fire_ns = 0,
        .active = false,
        .handle = 0,
    }} ** 16,
    entry_count: u8 = 0,
    next_handle: u64 = 1,
    running: bool = false,
    thread: ?std.Thread = null,
    mutex: std.Thread.Mutex = .{},

    pub fn init() StdScheduler {
        return .{};
    }

    pub fn start(self: *StdScheduler) void {
        self.running = true;
        self.thread = std.Thread.spawn(.{}, tickLoop, .{self}) catch null;
    }

    pub fn stop(self: *StdScheduler) void {
        self.running = false;
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    fn tickLoop(self: *StdScheduler) void {
        while (self.running) {
            std.Thread.sleep(10_000_000); // 10ms tick
            self.mutex.lock();
            const now: u64 = @intCast(std.time.nanoTimestamp());
            for (&self.entries) |*entry| {
                if (entry.active and (now - entry.last_fire_ns >= entry.interval_ns)) {
                    entry.last_fire_ns = now;
                    const cb = entry.callback;
                    const ctx = entry.cb_ctx;
                    self.mutex.unlock();
                    cb(ctx);
                    self.mutex.lock();
                }
            }
            self.mutex.unlock();
        }
    }

    pub fn vtable(self: *StdScheduler) SchedulerVTable {
        return .{
            .schedule_fn = stdSchedule,
            .cancel_fn = stdCancel,
            .context = @ptrCast(self),
        };
    }

    fn stdSchedule(callback: *const fn (?*anyopaque) callconv(.c) void, interval_ms: u64, cb_ctx: ?*anyopaque, ctx: ?*anyopaque) callconv(.c) u64 {
        const self: *StdScheduler = @ptrCast(@alignCast(ctx.?));
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.entry_count >= 16) return 0;

        const handle = self.next_handle;
        self.next_handle += 1;

        self.entries[self.entry_count] = .{
            .callback = callback,
            .interval_ns = interval_ms * 1_000_000,
            .cb_ctx = cb_ctx,
            .last_fire_ns = @intCast(std.time.nanoTimestamp()),
            .active = true,
            .handle = handle,
        };
        self.entry_count += 1;

        return handle;
    }

    fn stdCancel(handle: u64, ctx: ?*anyopaque) callconv(.c) void {
        const self: *StdScheduler = @ptrCast(@alignCast(ctx.?));
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.entries[0..self.entry_count]) |*entry| {
            if (entry.active and entry.handle == handle) {
                entry.active = false;
                return;
            }
        }
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "noop scheduler schedule returns 0" {
    const handle = noop_scheduler.schedule(noopCallback, 1000, null);
    try std.testing.expectEqual(@as(u64, 0), handle);
}

test "noop scheduler cancel is safe" {
    noop_scheduler.cancel(0);
}

fn noopCallback(_: ?*anyopaque) callconv(.c) void {}

test "StdScheduler init" {
    var sched = StdScheduler.init();
    _ = &sched;
    try std.testing.expectEqual(@as(u8, 0), sched.entry_count);
}
