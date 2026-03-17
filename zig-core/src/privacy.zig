// Terra Zig Core — privacy.zig
// ContentPolicy, RedactionStrategy, HMAC-SHA256 — STUB (to be implemented by agent)

const std = @import("std");

pub const ContentPolicy = enum(u8) {
    never = 0,
    opt_in = 1,
    always = 2,
};

pub const RedactionStrategy = enum(u8) {
    drop = 0,
    length_only = 1,
    hmac_sha256 = 2,
    sha256 = 3, // Legacy: plain SHA256 without HMAC key
};

pub const RedactedValue = union(enum) {
    dropped: void,
    length: usize,
    hash: [64]u8, // hex-encoded SHA256/HMAC
    hash_len: u8,
};

pub fn shouldCapture(policy: ContentPolicy, include_content: bool) bool {
    return switch (policy) {
        .never => false,
        .always => true,
        .opt_in => include_content,
    };
}

pub fn hmacSha256(key: []const u8, data: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    var hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
    hmac.update(data);
    hmac.final(&out);
    return out;
}

pub fn sha256(data: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &out, .{});
    return out;
}

pub fn redact(strategy: RedactionStrategy, content: []const u8, hmac_key: ?[]const u8) RedactedValue {
    return switch (strategy) {
        .drop => .{ .dropped = {} },
        .length_only => .{ .length = content.len },
        .hmac_sha256 => blk: {
            if (hmac_key) |key| {
                const hash = hmacSha256(key, content);
                var hex: [64]u8 = undefined;
                hex = std.fmt.bytesToHex(&hash, .lower);
                break :blk .{ .hash = hex };
            } else {
                // Fallback to plain SHA256 if no key provided
                const hash = sha256(content);
                var hex: [64]u8 = undefined;
                hex = std.fmt.bytesToHex(&hash, .lower);
                break :blk .{ .hash = hex };
            }
        },
        .sha256 => blk: {
            const hash = sha256(content);
            var hex: [64]u8 = undefined;
            hex = std.fmt.bytesToHex(&hash, .lower);
            break :blk .{ .hash = hex };
        },
    };
}

// ── Tests ───────────────────────────────────────────────────────────────
test "shouldCapture policy matrix" {
    // never: always false regardless of include_content
    try std.testing.expect(!shouldCapture(.never, false));
    try std.testing.expect(!shouldCapture(.never, true));
    // always: always true regardless of include_content
    try std.testing.expect(shouldCapture(.always, false));
    try std.testing.expect(shouldCapture(.always, true));
    // opt_in: depends on include_content
    try std.testing.expect(!shouldCapture(.opt_in, false));
    try std.testing.expect(shouldCapture(.opt_in, true));
}

test "HMAC-SHA256 produces 32 bytes" {
    const result = hmacSha256("secret-key", "hello world");
    try std.testing.expectEqual(@as(usize, 32), result.len);
    // Verify non-zero
    var all_zero = true;
    for (result) |b| {
        if (b != 0) all_zero = false;
    }
    try std.testing.expect(!all_zero);
}

test "SHA256 produces 32 bytes" {
    const result = sha256("hello world");
    try std.testing.expectEqual(@as(usize, 32), result.len);
}

test "HMAC-SHA256 deterministic" {
    const r1 = hmacSha256("key", "data");
    const r2 = hmacSha256("key", "data");
    try std.testing.expectEqualSlices(u8, &r1, &r2);
}

test "HMAC-SHA256 different keys produce different hashes" {
    const r1 = hmacSha256("key1", "data");
    const r2 = hmacSha256("key2", "data");
    try std.testing.expect(!std.mem.eql(u8, &r1, &r2));
}

test "redact drop" {
    const result = redact(.drop, "sensitive content", null);
    try std.testing.expectEqual(RedactedValue{ .dropped = {} }, result);
}

test "redact length_only" {
    const result = redact(.length_only, "hello", null);
    switch (result) {
        .length => |len| try std.testing.expectEqual(@as(usize, 5), len),
        else => return error.TestUnexpectedResult,
    }
}

test "redact hmac_sha256 with key" {
    const result = redact(.hmac_sha256, "content", "my-key");
    switch (result) {
        .hash => |_| {},
        else => return error.TestUnexpectedResult,
    }
}

test "redact hmac_sha256 without key falls back to SHA256" {
    const result = redact(.hmac_sha256, "content", null);
    switch (result) {
        .hash => |_| {},
        else => return error.TestUnexpectedResult,
    }
}

test "redact empty content" {
    const drop_result = redact(.drop, "", null);
    try std.testing.expectEqual(RedactedValue{ .dropped = {} }, drop_result);

    const len_result = redact(.length_only, "", null);
    switch (len_result) {
        .length => |len| try std.testing.expectEqual(@as(usize, 0), len),
        else => return error.TestUnexpectedResult,
    }
}
