import Foundation

enum LegalDocs {
  static func privacyPolicyURL() -> URL? {
    url(forInfoPlistKey: "TraceMacAppPrivacyPolicyURL")
  }

  static func eulaURL() -> URL? {
    url(forInfoPlistKey: "TraceMacAppEULAURL")
  }

  private static func url(forInfoPlistKey key: String) -> URL? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let url = URL(string: value)
    else {
      return nil
    }
    return url
  }
}
