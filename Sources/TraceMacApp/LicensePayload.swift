import Foundation

struct LicensePayload: Codable, Equatable {
  var version: Int
  var product: String
  var bundleIdentifier: String
  var licensee: String
  var email: String?
  var issuedAt: Date
  var expiresAt: Date?
  var graceDays: Int

  init(
    version: Int = 1,
    product: String,
    bundleIdentifier: String,
    licensee: String,
    email: String? = nil,
    issuedAt: Date,
    expiresAt: Date? = nil,
    graceDays: Int = 7
  ) {
    self.version = version
    self.product = product
    self.bundleIdentifier = bundleIdentifier
    self.licensee = licensee
    self.email = email
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
    self.graceDays = graceDays
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case product
    case bundleIdentifier = "bundle_id"
    case licensee
    case email
    case issuedAt = "issued_at"
    case expiresAt = "expires_at"
    case graceDays = "grace_days"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    product = try container.decode(String.self, forKey: .product)
    bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
    licensee = try container.decode(String.self, forKey: .licensee)
    email = try container.decodeIfPresent(String.self, forKey: .email)
    graceDays = try container.decodeIfPresent(Int.self, forKey: .graceDays) ?? 7

    let issuedAtSeconds = try container.decode(Int64.self, forKey: .issuedAt)
    issuedAt = Date(timeIntervalSince1970: TimeInterval(issuedAtSeconds))

    if let expiresAtSeconds = try container.decodeIfPresent(Int64.self, forKey: .expiresAt) {
      expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtSeconds))
    } else {
      expiresAt = nil
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(product, forKey: .product)
    try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
    try container.encode(licensee, forKey: .licensee)
    try container.encodeIfPresent(email, forKey: .email)
    try container.encode(graceDays, forKey: .graceDays)

    let issuedAtSeconds = Int64(issuedAt.timeIntervalSince1970.rounded(.down))
    try container.encode(issuedAtSeconds, forKey: .issuedAt)

    if let expiresAt {
      let expiresAtSeconds = Int64(expiresAt.timeIntervalSince1970.rounded(.down))
      try container.encode(expiresAtSeconds, forKey: .expiresAt)
    }
  }
}

