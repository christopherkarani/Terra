import CryptoKit
import Foundation
import Testing
@testable import TraceMacAppUI

@Test("Base64URL encodes URL-safe and round-trips")
func base64URLEncodesAndDecodes() throws {
  let data = Data([0, 1, 2, 3, 254, 255])
  let encoded = Base64URL.encode(data)
  #expect(!encoded.contains("+"))
  #expect(!encoded.contains("/"))
  #expect(!encoded.contains("="))

  let decoded = try Base64URL.decode(encoded)
  #expect(decoded == data)
}

@Test("LicenseKey parsing validates prefix + part count")
func licenseKeyParsingValidatesFormat() {
  #expect(throws: LicenseKeyError.self) {
    _ = try LicenseKey.parse("not-a-license")
  }
  #expect(throws: LicenseKeyError.self) {
    _ = try LicenseKey.parse("WRONG.\(Base64URL.encode(Data())).\(Base64URL.encode(Data()))")
  }
}

@Test("LicenseVerifier accepts a valid signed license key")
func licenseVerifierAcceptsValidSignature() throws {
  let privateKey = Curve25519.Signing.PrivateKey()
  let verifier = LicenseVerifier(publicKey: privateKey.publicKey, isConfigured: true)

  let payload = LicensePayload(
    product: LicenseManager.Product.name,
    bundleIdentifier: "com.terra.TraceMacApp",
    licensee: "Test User",
    email: "test@example.com",
    issuedAt: Date(timeIntervalSince1970: 1_000),
    expiresAt: nil,
    graceDays: 7
  )
  let payloadData = try JSONEncoder().encode(payload)
  let signature = try privateKey.signature(for: payloadData)

  let key = "\(LicenseKey.prefix).\(Base64URL.encode(payloadData)).\(Base64URL.encode(signature))"
  let verified = try verifier.verify(
    licenseKey: key,
    expectedBundleIdentifier: "com.terra.TraceMacApp",
    expectedProduct: LicenseManager.Product.name,
    now: Date(timeIntervalSince1970: 2_000)
  )

  #expect(verified.payload == payload)
  #expect(verified.isInGrace == false)
}

@Test("LicenseVerifier enforces expiration + grace window")
func licenseVerifierExpirationAndGrace() throws {
  let privateKey = Curve25519.Signing.PrivateKey()
  let verifier = LicenseVerifier(publicKey: privateKey.publicKey, isConfigured: true)

  let issuedAt = Date(timeIntervalSince1970: 1_000)
  let expiresAt = Date(timeIntervalSince1970: 1_200)

  let payload = LicensePayload(
    product: LicenseManager.Product.name,
    bundleIdentifier: "com.terra.TraceMacApp",
    licensee: "Grace User",
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    graceDays: 7
  )

  let payloadData = try JSONEncoder().encode(payload)
  let signature = try privateKey.signature(for: payloadData)
  let key = "\(LicenseKey.prefix).\(Base64URL.encode(payloadData)).\(Base64URL.encode(signature))"

  let withinGraceNow = expiresAt.addingTimeInterval(2 * 24 * 60 * 60)
  let withinGrace = try verifier.verify(
    licenseKey: key,
    expectedBundleIdentifier: "com.terra.TraceMacApp",
    expectedProduct: LicenseManager.Product.name,
    now: withinGraceNow
  )
  #expect(withinGrace.isInGrace == true)

  let afterGraceNow = expiresAt.addingTimeInterval(8 * 24 * 60 * 60)
  #expect(throws: LicenseVerificationError.self) {
    _ = try verifier.verify(
      licenseKey: key,
      expectedBundleIdentifier: "com.terra.TraceMacApp",
      expectedProduct: LicenseManager.Product.name,
      now: afterGraceNow
    )
  }
}

@Test("LicenseManager trial cannot be extended by backdating the clock")
@MainActor
func licenseManagerBackdatingDoesNotExtendTrial() {
  final class InMemoryStore: SecureStoring {
    private var storage: [String: Data] = [:]

    func readData(account: String) throws -> Data? { storage[account] }
    func writeData(_ data: Data, account: String) throws { storage[account] = data }
    func delete(account: String) throws { storage.removeValue(forKey: account) }
  }

  final class TestClock: Clock {
    var now: Date
    init(now: Date) { self.now = now }
  }

  let store = InMemoryStore()
  let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
  let verifier = LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey, isConfigured: true)

  let manager = LicenseManager(clock: clock, store: store, verifier: verifier)
  manager.refresh()

  clock.now = Date(timeIntervalSince1970: 1_000 + (15 * 24 * 60 * 60))
  manager.refresh()
  #expect({
    if case .expiredTrial = manager.status { return true }
    return false
  }())

  // Backdate the clock; trial should not become active again.
  clock.now = Date(timeIntervalSince1970: 1_000 + (2 * 24 * 60 * 60))
  manager.refresh()
  #expect({
    if case .expiredTrial = manager.status { return true }
    return false
  }())
}

