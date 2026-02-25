import OpenTelemetryApi

public enum TerraTelemetryClassifier {
  public static let recommendationEventName = "terra.recommendation"
  public static let recommendationAttributePrefix = "terra.recommendation."

  public static let anomalyNamePrefix = "terra.anomaly"
  public static let anomalyAttributePrefix = "terra.anomaly."

  public static let policyNamePrefix = "terra.policy"
  public static let auditNamePrefix = "terra.audit"
  public static let policyAttributePrefix = "terra.policy."
  public static let auditAttributePrefix = "terra.audit."

  public static let lifecycleEventNames: Set<String> = [
    "terra.first_token",
    "terra.token.lifecycle",
    "terra.stream.lifecycle",
  ]
  public static let lifecycleAttributeKeys: Set<String> = [
    "terra.token.stage",
    "terra.token.index",
    "terra.token.gap_ms",
    "terra.stream.chunk_count",
    "terra.stream.output_tokens",
    "terra.stream.time_to_first_token_ms",
  ]

  public static let hardwareNamePrefixes = [
    "terra.process.",
    "terra.hw.",
  ]
  public static let hardwareAttributeKeys: Set<String> = [
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

  public static func isRecommendationEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name == recommendationEventName {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(recommendationAttributePrefix) })
  }

  public static func isAnomalyEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name.hasPrefix(anomalyNamePrefix) {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(anomalyAttributePrefix) })
  }

  public static func isPolicyEvent(
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

  public static func isLifecycleEvent(
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

  public static func isHardwareEvent(
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
