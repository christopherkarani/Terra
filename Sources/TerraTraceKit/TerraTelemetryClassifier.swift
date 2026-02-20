import OpenTelemetryApi

package enum TerraTelemetryClassifier {
  package static let recommendationEventName = "terra.recommendation"
  package static let recommendationAttributePrefix = "terra.recommendation."

  package static let anomalyNamePrefix = "terra.anomaly"
  package static let anomalyAttributePrefix = "terra.anomaly."

  package static let policyNamePrefix = "terra.policy"
  package static let auditNamePrefix = "terra.audit"
  package static let policyAttributePrefix = "terra.policy."
  package static let auditAttributePrefix = "terra.audit."

  package static let lifecycleEventNames: Set<String> = [
    "terra.first_token",
    "terra.token.lifecycle",
    "terra.stream.lifecycle",
  ]
  package static let lifecycleAttributeKeys: Set<String> = [
    "terra.token.stage",
    "terra.token.index",
    "terra.token.gap_ms",
    "terra.stream.chunk_count",
    "terra.stream.output_tokens",
    "terra.stream.time_to_first_token_ms",
  ]

  package static let hardwareNamePrefixes = [
    "terra.process.",
    "terra.hw.",
  ]
  package static let hardwareAttributeKeys: Set<String> = [
    "terra.process.thermal_state",
    "terra.process.memory_resident_delta_mb",
    "terra.process.memory_peak_mb",
    "terra.hw.power_state",
    "terra.hw.memory_pressure",
    "terra.hw.rss_mb",
    "terra.hw.memory_churn_mb",
    "terra.hw.gpu_occupancy_pct",
    "terra.hw.ane_utilization_pct",
  ]

  package static func isRecommendationEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name == recommendationEventName {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(recommendationAttributePrefix) })
  }

  package static func isAnomalyEvent(
    name: String,
    attributes: [String: OpenTelemetryApi.AttributeValue]
  ) -> Bool {
    if name.hasPrefix(anomalyNamePrefix) {
      return true
    }
    return attributes.keys.contains(where: { $0.hasPrefix(anomalyAttributePrefix) })
  }

  package static func isPolicyEvent(
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

  package static func isLifecycleEvent(
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

  package static func isHardwareEvent(
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
