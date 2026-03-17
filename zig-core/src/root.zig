// Terra Zig Core — Library root
// Re-exports all public modules for the library target.

pub const models = @import("models.zig");
pub const constants = @import("constants.zig");
pub const clock = @import("clock.zig");
pub const privacy = @import("privacy.zig");
pub const config = @import("config.zig");
pub const span = @import("span.zig");
pub const store = @import("store.zig");
pub const transport = @import("transport.zig");
pub const scheduler = @import("scheduler.zig");
pub const storage = @import("storage.zig");
pub const metrics = @import("metrics.zig");
pub const otlp = @import("otlp.zig");
pub const processor = @import("processor.zig");
pub const resource = @import("resource.zig");
pub const terra = @import("terra.zig");
pub const c_api = @import("c_api.zig");
pub const test_harness = @import("test_harness.zig");

// Re-export primary public types at top level for convenience
pub const TerraInstance = terra.TerraInstance;
pub const TerraConfig = config.TerraConfig;
pub const Span = span.Span;
pub const SpanRecord = models.SpanRecord;
pub const TraceID = models.TraceID;
pub const SpanID = models.SpanID;
pub const SpanContext = models.SpanContext;

test {
    // Pull in all module tests
    @import("std").testing.refAllDecls(@This());
}
