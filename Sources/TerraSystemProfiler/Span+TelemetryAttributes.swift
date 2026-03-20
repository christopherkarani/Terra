import OpenTelemetryApi

extension Span {
  /// Sets attributes from any `TelemetryAttributeConvertible` conforming type.
  public func setAttributes(_ provider: some TelemetryAttributeConvertible) {
    for (key, value) in provider.telemetryAttributes {
      setAttribute(key: key, value: value)
    }
  }
}
