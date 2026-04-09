import Foundation

#if canImport(Security)
  import Security
#endif

extension Terra {
  package static func resolveInstallationIdentity(explicit: String?, namespace: String) -> String {
    if let explicit = normalizedInstallationIdentity(explicit) {
      return explicit
    }

    let normalizedNamespace = normalizedInstallationNamespace(namespace)
    if let existing = readInstallationIdentityFromKeychain(namespace: normalizedNamespace)
      ?? readInstallationIdentityFromDefaults(namespace: normalizedNamespace)
    {
      return existing
    }

    let generated = UUID().uuidString.lowercased()
    if !storeInstallationIdentityToKeychain(generated, namespace: normalizedNamespace) {
      storeInstallationIdentityToDefaults(generated, namespace: normalizedNamespace)
    } else {
      storeInstallationIdentityToDefaults(generated, namespace: normalizedNamespace)
    }
    return generated
  }
}

private extension Terra {
  static let installationIdentityKeychainService = "io.opentelemetry.terra.installation"
  static let installationIdentityDefaultsPrefix = "io.opentelemetry.terra.installation."

  static func normalizedInstallationIdentity(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  static func normalizedInstallationNamespace(_ namespace: String) -> String {
    let trimmed = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "default" : trimmed
  }

  static func readInstallationIdentityFromDefaults(namespace: String) -> String? {
    UserDefaults.standard.string(forKey: installationIdentityDefaultsPrefix + namespace)
  }

  static func storeInstallationIdentityToDefaults(_ installationID: String, namespace: String) {
    UserDefaults.standard.set(installationID, forKey: installationIdentityDefaultsPrefix + namespace)
  }

  static func readInstallationIdentityFromKeychain(namespace: String) -> String? {
    #if canImport(Security)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: installationIdentityKeychainService,
        kSecAttrAccount as String: namespace,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess, let data = result as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    #else
      return nil
    #endif
  }

  static func storeInstallationIdentityToKeychain(_ installationID: String, namespace: String) -> Bool {
    #if canImport(Security)
      let data = Data(installationID.utf8)
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: installationIdentityKeychainService,
        kSecAttrAccount as String: namespace,
      ]
      let attributes: [String: Any] = [
        kSecValueData as String: data,
      ]
      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      if updateStatus == errSecSuccess {
        return true
      }
      if updateStatus != errSecItemNotFound {
        return false
      }
      var create = query
      create[kSecValueData as String] = data
      return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    #else
      return false
    #endif
  }
}
