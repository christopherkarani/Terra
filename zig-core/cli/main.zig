const std = @import("std");
const doctor = @import("doctor.zig");
const validate = @import("validate.zig");
const listen = @import("listen.zig");
const trace = @import("trace.zig");

const Command = struct {
    name: []const u8,
    description: []const u8,
    handler: *const fn ([]const []const u8) void,
};

const commands = [_]Command{
    .{ .name = "doctor", .description = "Check Zig version, platform, library info", .handler = doctor.run },
    .{ .name = "validate", .description = "Validate an OTLP protobuf trace file", .handler = validate.run },
    .{ .name = "listen", .description = "Start OTLP HTTP listener (stub)", .handler = listen.run },
    .{ .name = "trace", .description = "Decode OTLP trace file (stub)", .handler = trace.run },
};

fn printUsage() void {
    std.debug.print("\n", .{});
    std.debug.print("terra-cli — Terra Zig Core command-line tool\n\n", .{});
    std.debug.print("Usage: terra <command> [args...]\n\n", .{});
    std.debug.print("Commands:\n", .{});
    for (&commands) |cmd| {
        std.debug.print("  {s:<12} {s}\n", .{ cmd.name, cmd.description });
    }
    std.debug.print("\nRun 'terra <command> --help' for more information.\n\n", .{});
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    // Skip program name
    const args = raw_args[1..];

    if (args.len == 0) {
        printUsage();
        return;
    }

    const cmd_name = args[0];
    const cmd_args = args[1..];

    for (&commands) |cmd| {
        if (std.mem.eql(u8, cmd_name, cmd.name)) {
            cmd.handler(cmd_args);
            return;
        }
    }

    std.debug.print("Unknown command: {s}\n", .{cmd_name});
    printUsage();
}

test {
    // Pull in tests from submodules
    _ = doctor;
    _ = validate;
}
