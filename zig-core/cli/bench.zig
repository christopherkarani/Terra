// Terra Zig Core — bench.zig
// Benchmark harness: measures span throughput with noop transport.
//
// Usage:
//   zig build bench          (standalone executable)
//   bench.run(args)          (called from CLI main.zig)

const std = @import("std");
const terra = @import("terra");

const TerraInstance = terra.terra.TerraInstance;
const TerraConfig = terra.config.TerraConfig;
const constants = terra.constants;

// ── Configuration ───────────────────────────────────────────────────────
const WARMUP_SPANS: u64 = 10_000;
const BENCH_SPANS: u64 = 1_000_000;
const MAX_SPANS_CAPACITY: u32 = 4096; // ring buffer size for benchmark

// ── Entry point (standalone executable) ────────────────────────────────
pub fn main() !void {
    run(&.{});
}

// ── Callable from CLI main.zig ─────────────────────────────────────────
pub fn run(_: []const []const u8) void {
    std.debug.print("\n", .{});
    std.debug.print("=== Terra Zig Core Benchmark ===\n", .{});
    std.debug.print("\n", .{});

    // Create instance with noop transport (default) and page_allocator
    var cfg = TerraConfig.default();
    cfg.max_spans = MAX_SPANS_CAPACITY;
    cfg.batch_size = MAX_SPANS_CAPACITY;

    const inst = TerraInstance.create(std.heap.page_allocator, cfg) catch {
        std.debug.print("ERROR: failed to create TerraInstance\n", .{});
        return;
    };
    defer inst.destroy();

    // ── Warmup phase ────────────────────────────────────────────────────
    std.debug.print("Warming up ({d} spans)...\n", .{WARMUP_SPANS});
    runSpanBatch(inst, WARMUP_SPANS);
    inst.reset();

    // ── Benchmark phase ─────────────────────────────────────────────────
    std.debug.print("Benchmarking ({d} spans)...\n", .{BENCH_SPANS});

    const start_ns = std.time.nanoTimestamp();
    runSpanBatch(inst, BENCH_SPANS);
    const end_ns = std.time.nanoTimestamp();

    const elapsed_ns: u64 = @intCast(end_ns - start_ns);
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const elapsed_s = elapsed_ms / 1_000.0;

    // ── Calculate metrics ───────────────────────────────────────────────
    const spans_per_sec: f64 = if (elapsed_s > 0)
        @as(f64, @floatFromInt(BENCH_SPANS)) / elapsed_s
    else
        0;

    // Approximate memory per span: Span struct size (stack, not heap)
    const span_size = @sizeOf(terra.span.Span);

    // ── Report ──────────────────────────────────────────────────────────
    std.debug.print("\n", .{});
    std.debug.print("=== Results ===\n", .{});
    std.debug.print("  Spans created:     {d}\n", .{BENCH_SPANS});
    std.debug.print("  Total time:        {d:.2} ms\n", .{elapsed_ms});
    std.debug.print("  Throughput:        {d:.0} spans/sec\n", .{spans_per_sec});
    std.debug.print("  Span struct size:  {d} bytes\n", .{span_size});
    std.debug.print("  Spans dropped:     {d}\n", .{inst.spansDropped()});
    std.debug.print("\n", .{});
    std.debug.print("  Operations per span:\n", .{});
    std.debug.print("    - create span (inference)\n", .{});
    std.debug.print("    - set 8 attributes (4 string, 2 int, 1 double, 1 bool)\n", .{});
    std.debug.print("    - add 1 event\n", .{});
    std.debug.print("    - end span\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Mode: single-threaded, noop transport\n", .{});
    std.debug.print("  Ring buffer capacity: {d} slots\n", .{MAX_SPANS_CAPACITY});
    std.debug.print("\n", .{});
}

// ── Core benchmark loop ────────────────────────────────────────────────
// Each iteration: create inference span, set 8 attributes, add 1 event, end span.
fn runSpanBatch(inst: *TerraInstance, count: u64) void {
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const span = inst.beginInferenceSpan(null, "bench-model-7b", false) orelse {
            // Ring buffer full — drain completed spans to free slots
            var drain_buf: [256]terra.models.SpanRecord = undefined;
            _ = inst.drainSpans(&drain_buf);
            // Retry once after drain
            const retry = inst.beginInferenceSpan(null, "bench-model-7b", false) orelse continue;
            populateAndEnd(inst, retry);
            continue;
        };
        populateAndEnd(inst, span);
    }
}

fn populateAndEnd(inst: *TerraInstance, span: *terra.span.Span) void {
    // 4 string attributes
    span.setString(constants.keys.gen_ai.request_model, "bench-model-7b");
    span.setString(constants.keys.gen_ai.operation_name, "inference");
    span.setString(constants.keys.gen_ai.provider_name, "terra-bench");
    span.setString(constants.keys.gen_ai.response_model, "bench-model-7b");

    // 2 int attributes
    span.setInt(constants.keys.gen_ai.request_max_tokens, 2048);
    span.setInt(constants.keys.gen_ai.usage_output_tokens, 512);

    // 1 double attribute
    span.setDouble(constants.keys.gen_ai.request_temperature, 0.7);

    // 1 bool attribute
    span.setBool(constants.keys.gen_ai.request_stream, false);

    // 1 event
    span.addEvent("gen_ai.content.prompt");

    // End span
    inst.endSpan(span);
}
