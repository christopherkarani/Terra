// Terra Zig Core — config.zig
// TerraConfig with all fields, validation, defaults.

const std = @import("std");
const privacy = @import("privacy.zig");
const clock = @import("clock.zig");
const transport = @import("transport.zig");
const scheduler = @import("scheduler.zig");
const storage = @import("storage.zig");

pub const ConfigError = enum {
    max_spans_zero,
    batch_size_exceeds_max_spans,
    flush_interval_zero,
    max_attributes_zero,
    max_events_zero,
};

pub const TerraConfig = struct {
    // Ring buffer capacity
    max_spans: u32 = 1024,
    // Attribute limits
    max_attributes_per_span: u16 = 64,
    max_events_per_span: u16 = 8,
    max_event_attrs: u16 = 4,
    // Batching
    batch_size: u32 = 256,
    flush_interval_ms: u64 = 5000,
    // Privacy
    content_policy: privacy.ContentPolicy = .never,
    redaction_strategy: privacy.RedactionStrategy = .hmac_sha256,
    hmac_key: ?[*:0]const u8 = null,
    emit_legacy_sha256: bool = false,
    // Service metadata
    service_name: [*:0]const u8 = "unknown",
    service_version: [*:0]const u8 = "0.0.0",
    // OTLP endpoint
    otlp_endpoint: [*:0]const u8 = "http://localhost:4318",
    // Clock
    clock_fn: clock.ClockFn = clock.stdClock,
    clock_ctx: ?*anyopaque = null,
    // Transport vtable
    transport_vtable: transport.TransportVTable = transport.noop_transport,
    // Scheduler vtable
    scheduler_vtable: scheduler.SchedulerVTable = scheduler.noop_scheduler,
    // Storage vtable
    storage_vtable: storage.StorageVTable = storage.noop_storage,
    // Allocator (for runtime allocations)
    allocator: std.mem.Allocator = std.heap.page_allocator,

    pub fn default() TerraConfig {
        return .{};
    }

    pub fn validate(self: TerraConfig) ?ConfigError {
        if (self.max_spans == 0) return .max_spans_zero;
        if (self.batch_size > self.max_spans) return .batch_size_exceeds_max_spans;
        if (self.flush_interval_ms == 0) return .flush_interval_zero;
        if (self.max_attributes_per_span == 0) return .max_attributes_zero;
        if (self.max_events_per_span == 0) return .max_events_zero;
        return null;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "default config validates" {
    const cfg = TerraConfig.default();
    try std.testing.expectEqual(@as(?ConfigError, null), cfg.validate());
}

test "zero max_spans rejected" {
    var cfg = TerraConfig.default();
    cfg.max_spans = 0;
    try std.testing.expectEqual(@as(?ConfigError, .max_spans_zero), cfg.validate());
}

test "batch_size exceeding max_spans rejected" {
    var cfg = TerraConfig.default();
    cfg.batch_size = 2048;
    cfg.max_spans = 1024;
    try std.testing.expectEqual(@as(?ConfigError, .batch_size_exceeds_max_spans), cfg.validate());
}

test "zero flush_interval rejected" {
    var cfg = TerraConfig.default();
    cfg.flush_interval_ms = 0;
    try std.testing.expectEqual(@as(?ConfigError, .flush_interval_zero), cfg.validate());
}

test "default privacy settings" {
    const cfg = TerraConfig.default();
    try std.testing.expectEqual(privacy.ContentPolicy.never, cfg.content_policy);
    try std.testing.expectEqual(privacy.RedactionStrategy.hmac_sha256, cfg.redaction_strategy);
}

test "default service metadata" {
    const cfg = TerraConfig.default();
    try std.testing.expectEqualStrings("unknown", std.mem.sliceTo(cfg.service_name, 0));
    try std.testing.expectEqualStrings("0.0.0", std.mem.sliceTo(cfg.service_version, 0));
}

test "default otlp endpoint" {
    const cfg = TerraConfig.default();
    try std.testing.expectEqualStrings("http://localhost:4318", std.mem.sliceTo(cfg.otlp_endpoint, 0));
}
