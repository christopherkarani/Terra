import CryptoKit
import Foundation

@MainActor
final class LicenseManager {
  enum Product {
    static let name = "TraceMacApp"
    static var bundleIdentifier: String {
      Bundle.main.bundleIdentifier ?? "com.terra.TraceMacApp"
    }
  }

  enum Feature {
    case watchFolder
  }

  enum Status: Equatable {
    case licensed(VerifiedLicense)
    case trial(daysRemaining: Int, endsAt: Date)
    case expiredTrial(endedAt: Date)
  }

  private enum KeychainAccount {
    static let licenseKey = "licenseKey"
    static let trialState = "trialState"
  }

  private let clock: Clock
  private let store: any SecureStoring
  private let verifier: LicenseVerifier

  private(set) var status: Status

  init(
    clock: Clock = SystemClock(),
    store: any SecureStoring = KeychainStore(service: Product.bundleIdentifier),
    verifier: LicenseVerifier = .production
  ) {
    self.clock = clock
    self.store = store
    self.verifier = verifier
    self.status = .trial(daysRemaining: 14, endsAt: clock.now)
    Task { await refresh() }
  }

  func refresh() async {
    let now = clock.now

    if let verified = try? await currentVerifiedLicense(now: now) {
      status = .licensed(verified)
      ensureTrialStateInitialized(now: now)
      return
    }

    let trial = loadOrCreateTrialState(now: now)
    status = Self.evaluateTrial(trial, now: trial.lastSeenDate)
  }

  func activate(licenseKey: String) async throws {
    let now = clock.now
    _ = try verifier.verify(
      licenseKey: licenseKey,
      expectedBundleIdentifier: Product.bundleIdentifier,
      expectedProduct: Product.name,
      now: now
    )

    try store.writeData(Data(licenseKey.utf8), account: KeychainAccount.licenseKey)
    await refresh()
  }

  func deactivate() async throws {
    try store.delete(account: KeychainAccount.licenseKey)
    await refresh()
  }

  func isFeatureEnabled(_ feature: Feature) -> Bool {
    switch status {
    case .licensed:
      return true
    case .trial:
      return true
    case .expiredTrial:
      switch feature {
      case .watchFolder:
        return false
      }
    }
  }

  private func currentVerifiedLicense(now: Date) async throws -> VerifiedLicense? {
    #if TRACE_MAC_APP_APPSTORE
      if await AppStoreReceiptVerifier.verifiedPurchaseExists() {
        return VerifiedLicense(
          payload: .init(
            product: Product.name,
            bundleIdentifier: Product.bundleIdentifier,
            licensee: "App Store",
            issuedAt: now,
            expiresAt: nil,
            graceDays: 0
          ),
          isInGrace: false
        )
      }
    #endif

    guard let data = try store.readData(account: KeychainAccount.licenseKey) else { return nil }
    guard let key = String(data: data, encoding: .utf8) else { return nil }
    return try verifier.verify(
      licenseKey: key,
      expectedBundleIdentifier: Product.bundleIdentifier,
      expectedProduct: Product.name,
      now: now
    )
  }

  private func loadOrCreateTrialState(now: Date) -> TrialState {
    let decoded: TrialState?
    if let data = try? store.readData(account: KeychainAccount.trialState) {
      decoded = try? JSONDecoder().decode(TrialState.self, from: data)
    } else {
      decoded = nil
    }

    let startDate = decoded?.startDate ?? now
    let lastSeenDate = max(decoded?.lastSeenDate ?? now, now)
    let trial = TrialState(startDate: startDate, lastSeenDate: lastSeenDate)
    saveTrialState(trial)
    return trial
  }

  private func ensureTrialStateInitialized(now: Date) {
    _ = loadOrCreateTrialState(now: now)
  }

  private func saveTrialState(_ state: TrialState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    try? store.writeData(data, account: KeychainAccount.trialState)
  }

  private static func evaluateTrial(_ trial: TrialState, now: Date) -> Status {
    let trialLengthDays = 14
    let secondsPerDay: TimeInterval = 24 * 60 * 60
    let endsAt = trial.startDate.addingTimeInterval(TimeInterval(trialLengthDays) * secondsPerDay)

    if now >= endsAt {
      return .expiredTrial(endedAt: endsAt)
    }

    let remainingSeconds = endsAt.timeIntervalSince(now)
    let daysRemaining = max(0, Int(ceil(remainingSeconds / secondsPerDay)))
    return .trial(daysRemaining: daysRemaining, endsAt: endsAt)
  }
}

// MARK: - Key Management
//
// The Ed25519 keypair used for license verification:
//   • Public key: embedded in Info.plist under "TraceMacAppLicensePublicKey" (Base64URL)
//   • Private key: stored in CI secrets / secure vault (NEVER in source)
//
// To sign a license key:
//   1. Encode a LicensePayload as JSON
//   2. Sign the JSON bytes with the Ed25519 private key
//   3. Format as: TERRA-LICENSE-1.<base64url-payload>.<base64url-signature>
//
// To rotate:
//   1. Generate a new Curve25519.Signing.PrivateKey()
//   2. Update Info.plist with Base64URL.encode(newKey.publicKey.rawRepresentation)
//   3. Re-sign all active licenses with the new private key

extension LicenseVerifier {
  static var production: LicenseVerifier {
    let keyString = Bundle.main.object(forInfoDictionaryKey: "TraceMacAppLicensePublicKey") as? String

    if
      let keyString, !keyString.isEmpty,
      let keyData = try? Base64URL.decode(keyString),
      keyData != Data(repeating: 0, count: 32),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    {
      return LicenseVerifier(publicKey: publicKey, isConfigured: true)
    }

    // Unconfigured: verification is disabled — verify() throws .notConfigured.
    // Uses a deterministic zero-byte placeholder (no ephemeral key generation).
    let zeroKey = try! Curve25519.Signing.PublicKey(rawRepresentation: Data(repeating: 1, count: 32))
    return LicenseVerifier(publicKey: zeroKey, isConfigured: false)
  }
}

#if TRACE_MAC_APP_APPSTORE
import StoreKit

enum AppStoreReceiptVerifier {
  /// Checks for a verified, non-revoked purchase using StoreKit 2.
  static func verifiedPurchaseExists() async -> Bool {
    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result,
         transaction.revocationDate == nil {
        return true
      }
    }
    return false
  }
}
#endif
