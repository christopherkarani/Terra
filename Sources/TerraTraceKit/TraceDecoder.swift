import Foundation
import OpenTelemetrySdk

/// Decodes comma-separated JSON arrays of `SpanData` from persistence files.
public struct TraceDecoder {
  /// Creates a decoder with default JSON decoding behavior.
  public init() {}

  /// Decodes spans from raw file data written by the persistence exporter.
  public func decodeSpans(from data: Data) throws -> [SpanData] {
    if data.isEmpty || data.isOnlyWhitespace {
      return []
    }
    guard data.lastNonWhitespaceByte == 0x2C else {
      throw TraceDecodingError.invalidFormat
    }

    var wrapped = Data("[".utf8)
    wrapped.append(data)
    wrapped.append(Data("null]".utf8))

    do {
      let decoder = JSONDecoder()
      let decoded = try decoder.decode([[SpanData]?].self, from: wrapped)
      return decoded.compactMap { $0 }.flatMap { $0 }
    } catch is DecodingError {
      throw TraceDecodingError.invalidFormat
    } catch {
      throw TraceDecodingError.decodingFailed(context: "\(error)")
    }
  }
}

private extension Data {
  var lastNonWhitespaceByte: UInt8? {
    for byte in self.reversed() {
      switch byte {
      case 0x20, 0x0A, 0x0D, 0x09:
        continue
      default:
        return byte
      }
    }
    return nil
  }

  var isOnlyWhitespace: Bool {
    for byte in self {
      switch byte {
      case 0x20, 0x0A, 0x0D, 0x09: // space, \n, \r, \t
        continue
      default:
        return false
      }
    }
    return true
  }
}
