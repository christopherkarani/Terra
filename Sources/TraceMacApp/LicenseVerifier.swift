import CryptoKit
import Foundation

struct LicenseVerifier {
  var publicKey: Curve25519.Signing.PublicKey
  var isConfigured: Bool

  func verify(
    licenseKey: String,
    expectedBundleIdentifier: String,
    expectedProduct: String,
    now: Date
  ) throws -> VerifiedLicense {
    guard isConfigured else {
      throw LicenseVerificationError.notConfigured
    }

    let parsed = try LicenseKey.parse(licenseKey)
    guard publicKey.isValidSignature(parsed.signature, for: parsed.payloadData) else {
      throw LicenseVerificationError.invalidSignature
    }

    let payload = try JSONDecoder().decode(LicensePayload.self, from: parsed.payloadData)
    guard payload.version == 1 else {
      throw LicenseVerificationError.unsupportedVersion
    }
    guard payload.bundleIdentifier == expectedBundleIdentifier else {
      throw LicenseVerificationError.wrongBundleIdentifier
    }
    guard payload.product == expectedProduct else {
      throw LicenseVerificationError.wrongProduct
    }

    if let expiresAt = payload.expiresAt {
      let grace = TimeInterval(max(0, payload.graceDays)) * 24 * 60 * 60
      let graceEndsAt = expiresAt.addingTimeInterval(grace)
      if now > graceEndsAt {
        throw LicenseVerificationError.expired
      }
      let isInGrace = now > expiresAt
      return VerifiedLicense(payload: payload, isInGrace: isInGrace)
    }

    return VerifiedLicense(payload: payload, isInGrace: false)
  }
}

struct VerifiedLicense: Equatable {
  var payload: LicensePayload
  var isInGrace: Bool
}

enum LicenseVerificationError: Error {
  case notConfigured
  case invalidSignature
  case unsupportedVersion
  case wrongBundleIdentifier
  case wrongProduct
  case expired
}
