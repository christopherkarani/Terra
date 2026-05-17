#if canImport(CTerraBridge)

import CTerraBridge
import Foundation

/// Test helper that manages a dedicated `terra_t*` instance for test isolation.
///
/// Usage:
/// ```swift
/// let capture = ZigSpanCapture()
/// // ... exercise code that creates spans via the Zig core ...
/// let spans = capture.finishedSpans()
/// // assert on spans
/// capture.reset()
/// ```
final class ZigSpanCapture {
  let instance: OpaquePointer  // terra_t*

  /// Creates a new Zig Terra instance with default configuration for testing.
  init() {
    var config = terra_config_t()
    config.max_spans = 256
    config.max_attributes_per_span = 64
    config.max_events_per_span = 32
    config.max_event_attrs = 16
    config.batch_size = 64
    config.flush_interval_ms = 1000
    config.content_policy = TERRA_CONTENT_ALWAYS
    config.redaction_strategy = TERRA_REDACT_DROP

    let serviceName = "terra-test"
    let serviceVersion = "0.0.1-test"
    let endpoint = "http://localhost:4318"

    // Store string pointers safely for the duration of init
    self.instance = serviceName.withCString { cName in
      serviceVersion.withCString { cVersion in
        endpoint.withCString { cEndpoint in
          config.service_name = cName
          config.service_version = cVersion
          config.otlp_endpoint = cEndpoint
          return terra_init(&config)!
        }
      }
    }
  }

  deinit {
    terra_shutdown(instance)
  }

  /// Drains all completed spans from the Zig ring buffer.
  ///
  /// Returns the number of spans drained. The actual span data is consumed
  /// by the Zig core's internal test drain mechanism.
  func drainSpanCount(maxSpans: UInt32 = 256) -> UInt32 {
    guard maxSpans > 0 else { return terra_test_drain_spans(instance, nil, 0) }
    let capacity = Int(maxSpans)
    let records = UnsafeMutablePointer<terra_test_span_record_t>.allocate(capacity: capacity)
    defer { records.deallocate() }
    records.initialize(repeating: terra_test_span_record_t(), count: capacity)
    defer { records.deinitialize(count: capacity) }
    return terra_test_drain_spans(instance, records, maxSpans)
  }

  /// Returns true if the instance is currently in the RUNNING state.
  var isRunning: Bool {
    terra_is_running(instance)
  }

  /// Returns the total number of spans dropped due to ring buffer overflow.
  var spansDropped: UInt64 {
    terra_spans_dropped(instance)
  }

  /// Resets the Zig instance state (clears spans, metrics). For testing only.
  func reset() {
    terra_test_reset(instance)
  }
}

#endif  // canImport(CTerraBridge)
