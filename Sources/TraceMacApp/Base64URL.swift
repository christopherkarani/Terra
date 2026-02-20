import Foundation

enum Base64URL {
  static func encode(_ data: Data) -> String {
    let base64 = data.base64EncodedString()
    return base64
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ string: String) throws -> Data {
    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let remainder = base64.count % 4
    if remainder != 0 {
      base64.append(String(repeating: "=", count: 4 - remainder))
    }

    guard let data = Data(base64Encoded: base64) else {
      throw Base64URLError.invalidEncoding
    }
    return data
  }
}

enum Base64URLError: Error {
  case invalidEncoding
}

