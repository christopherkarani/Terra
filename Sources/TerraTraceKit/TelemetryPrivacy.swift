import Foundation

enum TelemetryPrivacy {
  static let redactedValue = "[redacted: privacy-sensitive]"

  static let sensitiveAttributeKeys: Set<String> = [
    "gen_ai.prompt.content",
    "terra.prompt.length",
    "terra.prompt.hmac_sha256",
    "terra.prompt.sha256",
    "terra.safety.subject.length",
    "terra.safety.subject.hmac_sha256",
    "terra.safety.subject.sha256",
    "terra.anonymization.key_id",
    "terra.fm.tool.arguments",
    "terra.fm.tool.result",
  ]

  static func displayValue(forKey key: String, value: String) -> String {
    sensitiveAttributeKeys.contains(key) ? redactedValue : value
  }
}
