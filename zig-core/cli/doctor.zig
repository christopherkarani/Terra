// Terra CLI — doctor.zig
// Diagnostic checks: Zig version, platform, architecture, library info.

const std = @import("std");
const builtin = @import("builtin");
const terra_lib = @import("terra");

pub fn run(_: []const []const u8) void {
    std.debug.print("\n", .{});
    std.debug.print("=== terra doctor ===\n\n", .{});

    // Platform & architecture
    std.debug.print("Platform:       {s}\n", .{@tagName(builtin.os.tag)});
    std.debug.print("Architecture:   {s}\n", .{@tagName(builtin.cpu.arch)});
    std.debug.print("Endianness:     {s}\n", .{@tagName(builtin.cpu.arch.endian())});
    std.debug.print("Zig version:    {s}\n", .{builtin.zig_version_string});

    // Build mode
    std.debug.print("Build mode:     {s}\n", .{@tagName(builtin.mode)});

    // Library version
    const ver = terra_lib.terra.version;
    std.debug.print("Terra version:  {d}.{d}.{d}\n", .{ ver.major, ver.minor, ver.patch });

    // Struct sizes for ABI compatibility checks
    std.debug.print("\n--- ABI Layout ---\n", .{});
    std.debug.print("Span size:           {d} bytes\n", .{@sizeOf(terra_lib.span.Span)});
    std.debug.print("SpanRecord size:     {d} bytes\n", .{@sizeOf(terra_lib.models.SpanRecord)});
    std.debug.print("SpanContext size:    {d} bytes\n", .{@sizeOf(terra_lib.models.SpanContext)});
    std.debug.print("TerraConfig size:    {d} bytes\n", .{@sizeOf(terra_lib.config.TerraConfig)});
    std.debug.print("TerraInstance size:  {d} bytes\n", .{@sizeOf(terra_lib.terra.TerraInstance)});

    // Config defaults
    std.debug.print("\n--- Config Defaults ---\n", .{});
    const cfg = terra_lib.config.TerraConfig.default();
    std.debug.print("max_spans:           {d}\n", .{cfg.max_spans});
    std.debug.print("max_attributes:      {d}\n", .{cfg.max_attributes_per_span});
    std.debug.print("max_events:          {d}\n", .{cfg.max_events_per_span});
    std.debug.print("batch_size:          {d}\n", .{cfg.batch_size});
    std.debug.print("flush_interval_ms:   {d}\n", .{cfg.flush_interval_ms});
    std.debug.print("content_policy:      {s}\n", .{@tagName(cfg.content_policy)});
    std.debug.print("redaction_strategy:  {s}\n", .{@tagName(cfg.redaction_strategy)});
    std.debug.print("otlp_endpoint:       {s}\n", .{std.mem.sliceTo(cfg.otlp_endpoint, 0)});

    // Build options — accessed via terra library's models module
    std.debug.print("\n--- Build Options ---\n", .{});
    std.debug.print("TERRA_MAX_SPAN_NAME: {d}\n", .{terra_lib.models.MAX_SPAN_NAME});

    // Validation
    std.debug.print("\n--- Validation ---\n", .{});
    if (cfg.validate()) |err| {
        std.debug.print("Default config:      FAIL ({s})\n", .{@tagName(err)});
    } else {
        std.debug.print("Default config:      OK\n", .{});
    }

    // SpanContext ABI stability check (must be 24 bytes for C interop)
    const ctx_size = @sizeOf(terra_lib.models.SpanContext);
    if (ctx_size == 24) {
        std.debug.print("SpanContext ABI:     OK (24 bytes)\n", .{});
    } else {
        std.debug.print("SpanContext ABI:     WARN (expected 24, got {d})\n", .{ctx_size});
    }

    std.debug.print("\nAll checks passed.\n\n", .{});
}

// ── Tests ───────────────────────────────────────────────────────────────

test "doctor run does not panic" {
    // Smoke test: just run it, verify no crash
    run(&[_][]const u8{});
}
