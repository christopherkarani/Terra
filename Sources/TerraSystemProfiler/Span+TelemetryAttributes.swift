import OpenTelemetryApi

extension Span {
  /// Sets multiple attributes on this span from any `TelemetryAttributeConvertible` value.
  ///
  /// This provides a convenient way to attach profiler metrics to a span without
  /// manually iterating over the attribute dictionary:
  ///
  /// ```swift
  /// span.setAttributes(myPowerSummary)
  /// span.setAttributes(myThermalProfile)
  /// ```
  ///
  /// - Parameter provider: Any type conforming to ``TelemetryAttributeConvertible``.
  ///   Its `telemetryAttributes` dictionary is iterated and each key-value pair
  ///   is set as an attribute on this span.
  public func setAttributes(_ provider: some TelemetryAttributeConvertible) {
    for (key, value) in provider.telemetryAttributes {
      setAttribute(key: key, value: value)
    }
  }
}
