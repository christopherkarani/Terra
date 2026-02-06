import Foundation

struct LicenseKey: Equatable {
  static let prefix = "TERRA-LICENSE-1"

  var payloadData: Data
  var signature: Data

  static func parse(_ string: String) throws -> LicenseKey {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else {
      throw LicenseKeyError.invalidFormat
    }
    guard parts[0] == Self.prefix else {
      throw LicenseKeyError.invalidPrefix
    }
    let payloadData = try Base64URL.decode(String(parts[1]))
    let signature = try Base64URL.decode(String(parts[2]))
    return LicenseKey(payloadData: payloadData, signature: signature)
  }
}

enum LicenseKeyError: Error {
  case invalidFormat
  case invalidPrefix
}

