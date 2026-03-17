// Terra Zig Core — processor.zig
// Pipeline: SessionEnrichment -> BatchCollector -> PrivacyFilter -> OtlpSerializer -> TransportDispatch
// When TERRA_NO_STD=true: skip session enrichment, no retry backoff sleep.

const std = @import("std");
const build_options = @import("build_options");
const models = @import("models.zig");
const otlp = @import("otlp.zig");
const privacy = @import("privacy.zig");
const resource_mod = @import("resource.zig");
const transport_mod = @import("transport.zig");
const storage_mod = @import("storage.zig");
const constants = @import("constants.zig");

const no_std = build_options.TERRA_NO_STD;

const SpanRecord = models.SpanRecord;
const Attribute = models.Attribute;
const AttributeValue = models.AttributeValue;

// ── Pipeline configuration ──────────────────────────────────────────────
pub const PipelineConfig = struct {
    batch_size: u32 = 256,
    content_policy: privacy.ContentPolicy = .never,
    redaction_strategy: privacy.RedactionStrategy = .hmac_sha256,
    hmac_key: ?[]const u8 = null,
    emit_legacy_sha256: bool = false,
    service_name: []const u8 = "unknown",
    service_version: []const u8 = "0.0.0",
    session_id: ?[]const u8 = null,
    transport: transport_mod.TransportVTable = transport_mod.noop_transport,
    storage: storage_mod.StorageVTable = storage_mod.noop_storage,
    max_retries: u8 = 1,
    retry_base_ms: u64 = 100,
};

// ── Processor ───────────────────────────────────────────────────────────
pub const Processor = struct {
    config: PipelineConfig,
    batch_buf: []SpanRecord,
    batch_count: u32 = 0,
    allocator: std.mem.Allocator,
    total_processed: u64 = 0,
    total_dropped: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, cfg: PipelineConfig) !Processor {
        const batch_buf = try allocator.alloc(SpanRecord, cfg.batch_size);
        return .{
            .config = cfg,
            .batch_buf = batch_buf,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Processor) void {
        self.allocator.free(self.batch_buf);
    }

    /// Add spans to the batch. Returns number accepted.
    pub fn addSpans(self: *Processor, spans: []const SpanRecord, count: u32) u32 {
        var added: u32 = 0;
        var i: u32 = 0;
        while (i < count and self.batch_count < self.config.batch_size) : (i += 1) {
            self.batch_buf[self.batch_count] = spans[i];
            self.batch_count += 1;
            added += 1;
        }
        return added;
    }

    /// Check if batch is full.
    pub fn isBatchFull(self: *const Processor) bool {
        return self.batch_count >= self.config.batch_size;
    }

    /// Process and send the current batch. Returns true on success.
    pub fn flush(self: *Processor) bool {
        if (self.batch_count == 0) return true;

        // Stage 1: Session enrichment
        self.enrichBatch();

        // Stage 2: Serialize to OTLP
        var otlp_buf: [131072]u8 = undefined; // 128KB
        const resource_attrs = resource_mod.ResourceAttributes.build(
            self.config.service_name,
            self.config.service_version,
        );
        const encoded = otlp.encodeSpanBatch(
            self.batch_buf[0..self.batch_count],
            resource_attrs.slice(),
            &otlp_buf,
        ) orelse {
            self.total_dropped += self.batch_count;
            self.batch_count = 0;
            return false;
        };

        // Stage 4: Transport dispatch with retry
        const sent = self.sendWithRetry(encoded);

        self.total_processed += self.batch_count;
        self.batch_count = 0;
        return sent;
    }

    fn enrichBatch(self: *Processor) void {
        if (no_std) return; // Skip session enrichment on freestanding targets
        var i: u32 = 0;
        while (i < self.batch_count) : (i += 1) {
            var rec = &self.batch_buf[i];
            // Inject session.id if set
            if (self.config.session_id) |sid| {
                _ = rec.attributes.append(.{
                    .key = constants.keys.session_key.id,
                    .value = .{ .string = sid },
                });
            }
        }
    }

    fn sendWithRetry(self: *Processor, data: []const u8) bool {
        var attempt: u8 = 0;
        while (attempt <= self.config.max_retries) : (attempt += 1) {
            const result = self.config.transport.send(data);
            if (result == 0) return true;

            // Exponential backoff with cap (skipped on freestanding — no OS sleep)
            if (!no_std and attempt < self.config.max_retries) {
                const raw_backoff = self.config.retry_base_ms * (@as(u64, 1) << @intCast(attempt));
                const backoff_ms: u64 = @min(raw_backoff, 500);
                std.Thread.sleep(backoff_ms * 1_000_000);
            }
        }

        // All retries exhausted — fallback to storage
        _ = self.config.storage.write(data);
        return false;
    }

    pub fn reset(self: *Processor) void {
        self.batch_count = 0;
        self.total_processed = 0;
        self.total_dropped = 0;
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "Processor init and deinit" {
    var proc = try Processor.init(std.testing.allocator, .{});
    defer proc.deinit();
    try std.testing.expectEqual(@as(u32, 0), proc.batch_count);
}

test "Processor addSpans" {
    var proc = try Processor.init(std.testing.allocator, .{ .batch_size = 4 });
    defer proc.deinit();

    var recs: [2]SpanRecord = undefined;
    recs[0] = SpanRecord{};
    recs[0].setName("span1");
    recs[1] = SpanRecord{};
    recs[1].setName("span2");

    const added = proc.addSpans(&recs, 2);
    try std.testing.expectEqual(@as(u32, 2), added);
    try std.testing.expectEqual(@as(u32, 2), proc.batch_count);
}

test "Processor isBatchFull" {
    var proc = try Processor.init(std.testing.allocator, .{ .batch_size = 2 });
    defer proc.deinit();

    var recs: [2]SpanRecord = undefined;
    recs[0] = SpanRecord{};
    recs[1] = SpanRecord{};

    _ = proc.addSpans(&recs, 2);
    try std.testing.expect(proc.isBatchFull());
}

test "Processor flush with noop transport" {
    var proc = try Processor.init(std.testing.allocator, .{
        .batch_size = 4,
    });
    defer proc.deinit();

    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 2 };
    rec.span_id = models.SpanID{ .id = 3 };
    rec.setName("gen_ai.inference");
    rec.start_time_ns = 1000;
    rec.end_time_ns = 2000;

    _ = proc.addSpans(@as(*const [1]SpanRecord, &rec), 1);
    const result = proc.flush();
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u32, 0), proc.batch_count);
    try std.testing.expectEqual(@as(u64, 1), proc.total_processed);
}

test "Processor flush with buffer transport" {
    var bt = transport_mod.BufferTransport.init(std.testing.allocator);
    defer bt.deinit();

    var proc = try Processor.init(std.testing.allocator, .{
        .batch_size = 4,
        .transport = bt.vtable(),
    });
    defer proc.deinit();

    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 2 };
    rec.span_id = models.SpanID{ .id = 3 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    _ = proc.addSpans(@as(*const [1]SpanRecord, &rec), 1);
    const result = proc.flush();
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(usize, 1), bt.captures.items.len);
}

test "Processor flush empty batch" {
    var proc = try Processor.init(std.testing.allocator, .{});
    defer proc.deinit();

    const result = proc.flush();
    try std.testing.expect(result);
    try std.testing.expectEqual(@as(u64, 0), proc.total_processed);
}

test "Processor transport failure with storage fallback" {
    var bt = transport_mod.BufferTransport.init(std.testing.allocator);
    defer bt.deinit();
    bt.fail_next = true;

    var bs = storage_mod.BufferStorage.init(std.testing.allocator);
    defer bs.deinit();

    var proc = try Processor.init(std.testing.allocator, .{
        .batch_size = 4,
        .transport = bt.vtable(),
        .storage = bs.vtable(),
        .max_retries = 0, // No retries — fail immediately
        .retry_base_ms = 0,
    });
    defer proc.deinit();

    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    _ = proc.addSpans(@as(*const [1]SpanRecord, &rec), 1);
    const result = proc.flush();
    try std.testing.expect(!result); // Transport failed

    // Verify storage received fallback
    try std.testing.expect(bs.write_count > 0);
}

test "Processor session enrichment" {
    var bt = transport_mod.BufferTransport.init(std.testing.allocator);
    defer bt.deinit();

    var proc = try Processor.init(std.testing.allocator, .{
        .batch_size = 4,
        .transport = bt.vtable(),
        .session_id = "session-42",
    });
    defer proc.deinit();

    var rec = SpanRecord{};
    rec.trace_id = models.TraceID{ .hi = 1, .lo = 1 };
    rec.span_id = models.SpanID{ .id = 1 };
    rec.setName("test");
    rec.start_time_ns = 100;
    rec.end_time_ns = 200;

    _ = proc.addSpans(@as(*const [1]SpanRecord, &rec), 1);

    // After enrichment, batch should have session.id attribute
    proc.enrichBatch();
    var found_session = false;
    for (proc.batch_buf[0].attributes.slice()) |attr| {
        if (std.mem.eql(u8, attr.key, "session.id")) {
            found_session = true;
        }
    }
    try std.testing.expect(found_session);
}

test "Processor reset" {
    var proc = try Processor.init(std.testing.allocator, .{});
    defer proc.deinit();

    var rec = SpanRecord{};
    _ = proc.addSpans(@as(*const [1]SpanRecord, &rec), 1);
    proc.total_processed = 100;

    proc.reset();
    try std.testing.expectEqual(@as(u32, 0), proc.batch_count);
    try std.testing.expectEqual(@as(u64, 0), proc.total_processed);
}
