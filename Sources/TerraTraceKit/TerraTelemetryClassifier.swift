import OpenTelemetryApi

enum TerraTelemetryClassifier {
  static let recommendationEventName = "terra.recommendation"
  static let recommendationAttributePrefix = "terra.recommendation."

  static let anomalyNamePrefix = "terra.anomaly"
  static let anomalyAttributePrefix = "terra.anomaly."

  static let policyNamePrefix = "terra.policy"
  static let auditNamePrefix = "terra.audit"
  static let policyAttributePrefix = "terra.policy."
  static let auditAttributePrefix = "terra.audit."

  static let lifecycleEventNames: Set<String> = [
    "terra.first_token",
    "terra.token.lifecycle",
    "terra.stream.lifecycle",
  ]
  static let lifecycleAttributeKeys: Set<String> = [
    "terra.token.stage",
    "terra.token.index",
    "terra.token.gap_ms",
    "terra.stream.chunk_count",
    "terra.stream.output_tokens",
    "terra.stream.time_to_first_token_ms",
  ]

  static let hardwareNamePrefixes = [
    "terra.process.",
    "terra.hw.",
  ]
  static let hardwareAttributeKeys: Set<String> = [
    "terra.process.thermal_state",
    "process.memory.resident_delta_mb",
    "process.memory.peak_mb",
    "terra.hw.power_state",
    "terra.hw.memory_pressure",
    "terra.hw.rss_mb",
    "terra.hw.memory_churn_mb",
    "terra.hw.gpu_occupancy_pct",
    "terra.hw.ane_utilization_pct",
  ]

  static func isRecommendationEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name == recommendationEventName {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(recommendationAttributePrefix) })
  }

  static func isAnomalyEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name.hasPrefix(anomalyNamePrefix) {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(anomalyAttributePrefix) })
  }

  static func isPolicyEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name.hasPrefix(policyNamePrefix) || name.hasPrefix(auditNamePrefix) {
      return true
    }
    return attributes.keys.contains {
      $0.hasPrefix(policyAttributePrefix) || $0.hasPrefix(auditAttributePrefix)
    }
  }

  static func isLifecycleEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if lifecycleEventNames.contains(name) {
      return true
    }
    return attributes.keys.contains { key in
      key.hasPrefix("terra.token.") || lifecycleAttributeKeys.contains(key)
    }
  }

  static func isHardwareEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if hardwareNamePrefixes.contains(where: { name.hasPrefix($0) }) {
      return true
    }
    return attributes.keys.contains { key in
      key.hasPrefix("terra.process.")
        || key.hasPrefix("terra.hw.")
        || hardwareAttributeKeys.contains(key)
    }
  }
}
