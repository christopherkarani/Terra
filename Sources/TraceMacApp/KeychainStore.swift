import Foundation
import Security

struct KeychainStore {
  var service: String

  init(service: String) {
    self.service = service
  }

  func readData(account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      return item as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError(status: status)
    }
  }

  func writeData(_ data: Data, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let update: [String: Any] = [
      kSecValueData as String: data,
    ]

    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var insert = query
      insert[kSecValueData as String] = data
      let addStatus = SecItemAdd(insert as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError(status: addStatus)
      }
    default:
      throw KeychainError(status: status)
    }
  }

  func delete(account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
      return
    default:
      throw KeychainError(status: status)
    }
  }
}

protocol SecureStoring {
  func readData(account: String) throws -> Data?
  func writeData(_ data: Data, account: String) throws
  func delete(account: String) throws
}

extension KeychainStore: SecureStoring {}

struct KeychainError: Error {
  var status: OSStatus
}
