const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Comptime feature flags ──────────────────────────────────────────
    const no_std = b.option(bool, "TERRA_NO_STD", "Freestanding mode: disables HashMap dedup, file_storage, metrics, events") orelse false;
    const max_span_name = b.option(u32, "TERRA_MAX_SPAN_NAME", "Maximum span name length") orelse 128;
    const enable_metrics = b.option(bool, "TERRA_METRICS", "Enable metrics collection") orelse true;
    const max_dedup_entries = b.option(u32, "TERRA_MAX_DEDUP_ENTRIES", "Max dedup entries for NO_STD BoundedArray fallback") orelse 128;

    // ── Build options module ────────────────────────────────────────────
    const options = b.addOptions();
    options.addOption(bool, "TERRA_NO_STD", no_std);
    options.addOption(u32, "TERRA_MAX_SPAN_NAME", max_span_name);
    options.addOption(bool, "TERRA_METRICS", enable_metrics);
    options.addOption(u32, "TERRA_MAX_DEDUP_ENTRIES", max_dedup_entries);

    // ── Library module ──────────────────────────────────────────────────
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addOptions("build_options", options);

    // ── Library target: libtera (static) ────────────────────────────────
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "terra",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    // ── Library target: libtera (shared) ────────────────────────────────
    const shared_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_mod.addOptions("build_options", options);

    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "terra_shared",
        .root_module = shared_mod,
    });
    b.installArtifact(shared_lib);

    // ── CLI target: terra-cli ───────────────────────────────────────────
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_mod.addImport("terra", lib_mod);
    cli_mod.addOptions("build_options", options);

    const cli_exe = b.addExecutable(.{
        .name = "terra-cli",
        .root_module = cli_mod,
    });
    b.installArtifact(cli_exe);

    // ── Test step ───────────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addOptions("build_options", options);

    const lib_unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const cli_test_mod = b.createModule(.{
        .root_source_file = b.path("cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_test_mod.addImport("terra", lib_mod);
    cli_test_mod.addOptions("build_options", options);

    const cli_unit_tests = b.addTest(.{
        .root_module = cli_test_mod,
    });
    const run_cli_unit_tests = b.addRunArtifact(cli_unit_tests);

    const test_step = b.step("test", "Run all unit tests with leak detection");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_cli_unit_tests.step);

    // ── Benchmark step ──────────────────────────────────────────────────
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("cli/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("terra", lib_mod);
    bench_mod.addOptions("build_options", options);

    const bench_exe = b.addExecutable(.{
        .name = "terra-bench",
        .root_module = bench_mod,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench.step);
}
