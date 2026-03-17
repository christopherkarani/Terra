// Terra Zig Core — resource.zig
// Device resource attributes (comptime + runtime).

const std = @import("std");
const constants = @import("constants.zig");
const models = @import("models.zig");

const Attribute = models.Attribute;
const AttributeValue = models.AttributeValue;

// ── Comptime resource attributes ────────────────────────────────────────
pub const sdk_name = constants.sdk_name;
pub const sdk_version = constants.sdk_version;
pub const sdk_language = constants.sdk_language;

pub fn osName() []const u8 {
    const target = @import("builtin").target;
    return switch (target.os.tag) {
        .macos => "macos",
        .ios => "ios",
        .linux => "linux",
        .windows => "windows",
        .freestanding => "freestanding",
        else => "unknown",
    };
}

pub fn archName() []const u8 {
    const target = @import("builtin").target;
    return switch (target.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        .thumb => "thumb",
        .arm => "arm",
        else => "unknown",
    };
}

// ── Resource attribute builder ──────────────────────────────────────────
pub const ResourceAttributes = struct {
    attrs: [16]Attribute = undefined,
    count: u8 = 0,

    pub fn build(service_name: []const u8, service_version: []const u8) ResourceAttributes {
        var ra = ResourceAttributes{};
        ra.add(constants.keys.sdk.name, .{ .string = sdk_name });
        ra.add(constants.keys.sdk.version, .{ .string = sdk_version });
        ra.add(constants.keys.sdk.language, .{ .string = sdk_language });
        ra.add(constants.keys.service.name, .{ .string = service_name });
        ra.add(constants.keys.service.version, .{ .string = service_version });
        ra.add("os.type", .{ .string = osName() });
        ra.add("host.arch", .{ .string = archName() });
        ra.add(constants.keys.schema_version, .{ .string = constants.schema_version_value });
        return ra;
    }

    fn add(self: *ResourceAttributes, key: []const u8, value: AttributeValue) void {
        if (self.count >= 16) return;
        self.attrs[self.count] = .{ .key = key, .value = value };
        self.count += 1;
    }

    pub fn slice(self: *const ResourceAttributes) []const Attribute {
        return self.attrs[0..self.count];
    }
};

// ── Tests ───────────────────────────────────────────────────────────────
test "resource attributes have required fields" {
    const ra = ResourceAttributes.build("my-service", "1.0.0");
    try std.testing.expect(ra.count >= 5);

    var found_sdk_name = false;
    var found_service_name = false;
    for (ra.slice()) |attr| {
        if (std.mem.eql(u8, attr.key, constants.keys.sdk.name)) {
            found_sdk_name = true;
            try std.testing.expectEqualStrings("terra", attr.value.string);
        }
        if (std.mem.eql(u8, attr.key, constants.keys.service.name)) {
            found_service_name = true;
            try std.testing.expectEqualStrings("my-service", attr.value.string);
        }
    }
    try std.testing.expect(found_sdk_name);
    try std.testing.expect(found_service_name);
}

test "comptime os and arch detection" {
    const os = osName();
    try std.testing.expect(os.len > 0);
    const arch = archName();
    try std.testing.expect(arch.len > 0);
}
