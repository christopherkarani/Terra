import Foundation
import os

enum TelemetryPrivacy {
  static let redactedValue = "[redacted: privacy-sensitive]"

  static let sensitiveAttributeKeys: Set<String> =
    schemaSensitiveAttributeKeys() ?? fallbackSensitiveAttributeKeys

  /// Hard-coded fallback used when the shipped `Docs/telemetry-schema.json`
  /// resource cannot be located (e.g. the schema was excluded from the
  /// host bundle, or the framework is loaded outside SwiftPM).
  ///
  /// Audit-flag entries (`viewer_behavior == "privacy_audit_detail"`) are
  /// intentionally absent so that the boolean state survives the redaction
  /// predicate — redacting an audit signal would defeat its purpose.
  static let fallbackSensitiveAttributeKeys: Set<String> = [
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
    "terra.fm.tool.name",
    "terra.service.input_length",
  ]

  static func displayValue(forKey key: String, value: String) -> String {
    sensitiveAttributeKeys.contains(key) ? redactedValue : value
  }

  /// Parses a telemetry-schema document and returns the set of attribute keys
  /// that must be redacted before display. Audit-state flags
  /// (`viewer_behavior == "privacy_audit_detail"`) are deliberately excluded —
  /// they are non-content state booleans whose value is itself the audit signal.
  static func sensitiveKeys(fromSchemaData data: Data) -> Set<String>? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let registry = object["registry"] as? [[String: Any]]
    else { return nil }

    let keys = registry.compactMap { entry -> String? in
      guard
        let key = entry["key"] as? String,
        let viewerBehavior = entry["viewer_behavior"] as? String,
        viewerBehavior == "privacy_sensitive_detail" || fallbackSensitiveAttributeKeys.contains(key)
      else { return nil }
      return key
    }
    let result = Set(keys)
    return result.isEmpty ? nil : result
  }

  /// Returns true when the supplied span status description likely contains
  /// user-visible text rather than a short error code, and therefore should be
  /// redacted before display under non-`.always` content policies.
  ///
  /// The heuristic is intentionally conservative — it favours over-redaction
  /// of an opaque code over under-redaction of a sentence.
  static func shouldRedactStatusDescription(_ description: String) -> Bool {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    if trimmed.contains(" ") { return true }

    // Treat short tokens like "ECONNRESET", "E_TIMEOUT", "HTTP_500" as codes.
    if trimmed.count <= 32, isLikelyErrorCode(trimmed) {
      return false
    }
    return true
  }

  /// Returns true when an event name is not part of the known Terra event
  /// vocabulary and therefore should be treated as user-supplied content.
  static func shouldRedactEventName(_ name: String) -> Bool {
    if knownEventNames.contains(name) { return false }
    for prefix in knownEventNamePrefixes where name.hasPrefix(prefix) {
      return false
    }
    return true
  }

  // MARK: - Private helpers

  private static func isLikelyErrorCode(_ token: String) -> Bool {
    for scalar in token.unicodeScalars {
      let isUpper = (scalar.value >= 65 && scalar.value <= 90) // A-Z
      let isDigit = (scalar.value >= 48 && scalar.value <= 57) // 0-9
      let isUnderscore = scalar.value == 95
      let isHyphen = scalar.value == 45
      if !(isUpper || isDigit || isUnderscore || isHyphen) {
        return false
      }
    }
    return true
  }

  /// Known event names emitted by Terra itself. Anything outside this set or
  /// the prefix list is treated as user-supplied text.
  private static let knownEventNames: Set<String> = [
    "terra.first_token",
    "terra.token.lifecycle",
    "terra.stream.lifecycle",
    "terra.parent.explicit_ended",
    "terra.recommendation",
    "chunk.stream",
    "exception",
  ]

  private static let knownEventNamePrefixes: [String] = [
    "terra.anomaly",
    "terra.policy",
    "terra.audit",
    "terra.process.",
    "terra.hw.",
    "terra.memory.",
    "terra.cache.",
    "terra.exec.route.",
    "terra.espresso.",
    "terra.token.",
    "terra.stream.",
  ]

  private static let schemaLogger = Logger(subsystem: "dev.terra.tracekit", category: "telemetry-privacy")

  private static func schemaSensitiveAttributeKeys() -> Set<String>? {
    if let bundleURL = bundleSchemaURL(),
       let data = try? Data(contentsOf: bundleURL),
       let keys = sensitiveKeys(fromSchemaData: data) {
      return keys
    }

    for url in candidateSchemaURLs() {
      guard let data = try? Data(contentsOf: url),
            let keys = sensitiveKeys(fromSchemaData: data) else { continue }
      return keys
    }

    schemaLogger.debug("telemetry-schema.json not located via Bundle.module or cwd walk; using fallback set")
    return nil
  }

  /// Sentinel class used to locate the framework bundle that ships this
  /// source code. When SwiftPM bundles `Docs/telemetry-schema.json` as a
  /// resource (declared in Package.swift) the schema is sibling to this
  /// class's bundle and discoverable via `Bundle(for:)`. This works even
  /// when `Bundle.module` is not generated (e.g. CocoaPods, manual Xcode
  /// integration) because the lookup is purely runtime reflection.
  private final class BundleSentinel {}

  private static func bundleSchemaURL() -> URL? {
    let frameworkBundle = Bundle(for: BundleSentinel.self)
    if let url = frameworkBundle.url(forResource: "telemetry-schema", withExtension: "json") {
      return url
    }

    // SwiftPM emits the resource into a sibling `<Module>_<Module>.bundle`.
    // Look it up explicitly so we work whether the framework is statically
    // linked into the host executable or shipped as a dynamic framework.
    let candidates = [
      "TerraTraceKit_TerraTraceKit",
      "Terra_TerraTraceKit",
    ]
    for name in candidates {
      guard let bundleURL = frameworkBundle.url(forResource: name, withExtension: "bundle"),
            let nestedBundle = Bundle(url: bundleURL),
            let schemaURL = nestedBundle.url(forResource: "telemetry-schema", withExtension: "json")
      else { continue }
      return schemaURL
    }
    return nil
  }

  private static func candidateSchemaURLs() -> [URL] {
    var urls: [URL] = []
    let fileManager = FileManager.default
    var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

    for _ in 0..<8 {
      urls.append(directory.appendingPathComponent("Docs/telemetry-schema.json"))
      let parent = directory.deletingLastPathComponent()
      guard parent.path != directory.path else { break }
      directory = parent
    }

    return urls
  }
}
