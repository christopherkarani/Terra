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
    refresh()
  }

  func refresh() {
    let now = clock.now

    if let verified = try? currentVerifiedLicense(now: now) {
      status = .licensed(verified)
      ensureTrialStateInitialized(now: now)
      return
    }

    let trial = loadOrCreateTrialState(now: now)
    status = Self.evaluateTrial(trial, now: trial.lastSeenDate)
  }

  func activate(licenseKey: String) throws {
    let now = clock.now
    _ = try verifier.verify(
      licenseKey: licenseKey,
      expectedBundleIdentifier: Product.bundleIdentifier,
      expectedProduct: Product.name,
      now: now
    )

    try store.writeData(Data(licenseKey.utf8), account: KeychainAccount.licenseKey)
    refresh()
  }

  func deactivate() throws {
    try store.delete(account: KeychainAccount.licenseKey)
    refresh()
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

  private func currentVerifiedLicense(now: Date) throws -> VerifiedLicense? {
    #if TRACE_MAC_APP_APPSTORE
      if AppStoreReceiptVerifier.isReceiptPresent() {
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

extension LicenseVerifier {
  static var production: LicenseVerifier {
    let keyString = Bundle.main.object(forInfoDictionaryKey: "TraceMacAppLicensePublicKey") as? String

    if
      let keyString,
      let keyData = try? Base64URL.decode(keyString),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    {
      return LicenseVerifier(publicKey: publicKey, isConfigured: true)
    }

    // Unconfigured: verification is disabled and activation will show an actionable error.
    let placeholder = (try? Curve25519.Signing.PublicKey(rawRepresentation: Data(repeating: 0, count: 32)))
      ?? Curve25519.Signing.PrivateKey().publicKey
    return LicenseVerifier(publicKey: placeholder, isConfigured: false)
  }
}

#if TRACE_MAC_APP_APPSTORE
  enum AppStoreReceiptVerifier {
    static func isReceiptPresent() -> Bool {
      guard let url = Bundle.main.appStoreReceiptURL else { return false }
      return (try? Data(contentsOf: url)).map { !$0.isEmpty } ?? false
    }
  }
#endif
