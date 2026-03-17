// Terra Zig Core — mqtt_transport.zig
// MQTT QoS 1 transport stub for IoT devices.
//
// Wire format: raw OTLP protobuf as MQTT payload (no additional framing).
// The actual MQTT client implementation is platform-specific — this module wraps
// a platform-provided publish function behind a TransportVTable.
//
// Typical usage on an IoT device:
//   1. Firmware initializes MQTT client (e.g., Paho Embedded C, ESP-MQTT)
//   2. Passes the publish function pointer + client handle to MqttTransportConfig
//   3. Terra sends OTLP batches as MQTT messages to the configured topic

const std = @import("std");
const transport = @import("transport.zig");

// ── Configuration ─────────────────────────────────────────────────────────
pub const QOS_AT_MOST_ONCE: u8 = 0;
pub const QOS_AT_LEAST_ONCE: u8 = 1;
pub const QOS_EXACTLY_ONCE: u8 = 2;

pub const DEFAULT_TOPIC: [:0]const u8 = "/terra/traces";
pub const DEFAULT_QOS: u8 = QOS_AT_LEAST_ONCE;
pub const MAX_TOPIC_LEN: usize = 256;
pub const MAX_CLIENT_ID_LEN: usize = 128;

pub const MqttConfig = struct {
    /// Broker hostname (null-terminated).
    broker_host: [*:0]const u8,
    /// Broker port.
    broker_port: u16 = 1883,
    /// MQTT topic for trace data (null-terminated).
    topic: [*:0]const u8 = DEFAULT_TOPIC,
    /// MQTT client identifier (null-terminated).
    client_id: [*:0]const u8 = "terra-zig",
    /// QoS level (0, 1, or 2).
    qos: u8 = DEFAULT_QOS,

    /// Validate the configuration.
    pub fn validate(self: MqttConfig) bool {
        // Port must be non-zero
        if (self.broker_port == 0) return false;

        // QoS must be 0, 1, or 2
        if (self.qos > 2) return false;

        // broker_host must not be empty
        if (self.broker_host[0] == 0) return false;

        // topic must not be empty
        if (self.topic[0] == 0) return false;

        // client_id must not be empty
        if (self.client_id[0] == 0) return false;

        return true;
    }
};

// ── Platform publish function ─────────────────────────────────────────────
/// Platform-provided MQTT publish function signature.
/// The firmware provides this. Returns 0 on success, non-zero on error.
pub const MqttPublishFn = *const fn (
    topic: [*:0]const u8,
    data: [*]const u8,
    len: u32,
    qos: u8,
    ctx: ?*anyopaque,
) callconv(.c) c_int;

// ── MQTT Transport Context ────────────────────────────────────────────────
pub const MqttTransportConfig = struct {
    /// MQTT configuration (broker, topic, QoS).
    config: MqttConfig,
    /// Platform-provided MQTT publish function.
    publish_fn: MqttPublishFn,
    /// Opaque context passed to publish_fn (e.g., MQTT client handle).
    publish_ctx: ?*anyopaque = null,
};

// ── TransportVTable implementation ────────────────────────────────────────
fn mqttSend(data: [*]const u8, len: u32, ctx: ?*anyopaque) callconv(.c) c_int {
    const cfg: *MqttTransportConfig = @ptrCast(@alignCast(ctx orelse return -1));

    if (!cfg.config.validate()) return -1;

    return cfg.publish_fn(
        cfg.config.topic,
        data,
        len,
        cfg.config.qos,
        cfg.publish_ctx,
    );
}

fn mqttFlush(_: ?*anyopaque) callconv(.c) void {
    // MQTT publish is message-oriented — nothing to flush.
}

fn mqttShutdown(_: ?*anyopaque) callconv(.c) void {
    // The MQTT client lifecycle is owned by the platform — we don't disconnect here.
}

/// Create a TransportVTable backed by MQTT publish.
pub fn vtable(cfg: *MqttTransportConfig) transport.TransportVTable {
    return .{
        .send_fn = mqttSend,
        .flush_fn = mqttFlush,
        .shutdown_fn = mqttShutdown,
        .context = @ptrCast(cfg),
    };
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "MqttConfig validate: valid defaults" {
    const cfg = MqttConfig{
        .broker_host = "localhost",
    };
    try std.testing.expect(cfg.validate());
}

test "MqttConfig validate: custom port and QoS" {
    const cfg = MqttConfig{
        .broker_host = "mqtt.example.com",
        .broker_port = 8883,
        .topic = "/my/traces",
        .qos = QOS_EXACTLY_ONCE,
    };
    try std.testing.expect(cfg.validate());
}

test "MqttConfig validate: invalid port zero" {
    const cfg = MqttConfig{
        .broker_host = "localhost",
        .broker_port = 0,
    };
    try std.testing.expect(!cfg.validate());
}

test "MqttConfig validate: invalid QoS" {
    const cfg = MqttConfig{
        .broker_host = "localhost",
        .qos = 3,
    };
    try std.testing.expect(!cfg.validate());
}

test "MqttConfig validate: empty broker host" {
    const cfg = MqttConfig{
        .broker_host = "",
    };
    try std.testing.expect(!cfg.validate());
}

test "MqttConfig validate: empty topic" {
    const cfg = MqttConfig{
        .broker_host = "localhost",
        .topic = "",
    };
    try std.testing.expect(!cfg.validate());
}

test "MqttConfig validate: empty client_id" {
    const cfg = MqttConfig{
        .broker_host = "localhost",
        .client_id = "",
    };
    try std.testing.expect(!cfg.validate());
}

test "MQTT vtable creation" {
    var cfg = MqttTransportConfig{
        .config = .{ .broker_host = "localhost" },
        .publish_fn = testMqttPublish,
    };
    const vt = vtable(&cfg);
    try std.testing.expect(vt.send_fn == mqttSend);
    try std.testing.expect(vt.flush_fn == mqttFlush);
    try std.testing.expect(vt.shutdown_fn == mqttShutdown);
}

test "MQTT transport send via vtable" {
    const TestCtx = struct {
        var publish_called: bool = false;
        var last_qos: u8 = 0;
        var last_len: u32 = 0;
    };
    TestCtx.publish_called = false;

    var cfg = MqttTransportConfig{
        .config = .{
            .broker_host = "localhost",
            .qos = QOS_AT_LEAST_ONCE,
        },
        .publish_fn = struct {
            fn f(_: [*:0]const u8, _: [*]const u8, len: u32, qos: u8, _: ?*anyopaque) callconv(.c) c_int {
                TestCtx.publish_called = true;
                TestCtx.last_qos = qos;
                TestCtx.last_len = len;
                return 0;
            }
        }.f,
    };
    const vt = vtable(&cfg);
    const result = vt.send("otlp-payload");
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expect(TestCtx.publish_called);
    try std.testing.expectEqual(QOS_AT_LEAST_ONCE, TestCtx.last_qos);
    try std.testing.expectEqual(@as(u32, 12), TestCtx.last_len);
}

test "MQTT transport send null context returns error" {
    const result = mqttSend("x".ptr, 1, null);
    try std.testing.expectEqual(@as(c_int, -1), result);
}

test "MQTT transport send with invalid config returns error" {
    var cfg = MqttTransportConfig{
        .config = .{
            .broker_host = "localhost",
            .qos = 5, // invalid
        },
        .publish_fn = testMqttPublish,
    };
    const vt = vtable(&cfg);
    const result = vt.send("data");
    try std.testing.expectEqual(@as(c_int, -1), result);
}

test "MQTT default topic" {
    try std.testing.expectEqualStrings("/terra/traces", DEFAULT_TOPIC);
}

test "MQTT QoS constants" {
    try std.testing.expectEqual(@as(u8, 0), QOS_AT_MOST_ONCE);
    try std.testing.expectEqual(@as(u8, 1), QOS_AT_LEAST_ONCE);
    try std.testing.expectEqual(@as(u8, 2), QOS_EXACTLY_ONCE);
}

// ── Test helpers ──────────────────────────────────────────────────────────
fn testMqttPublish(_: [*:0]const u8, _: [*]const u8, _: u32, _: u8, _: ?*anyopaque) callconv(.c) c_int {
    return 0;
}
