import Compression
import Foundation

#if canImport(zlib)
  import zlib
#endif

enum OTLPContentEncoding: String, Sendable {
  case gzip
  case deflate
  case identity
}

enum OTLPDecompressor {
  static func decompress(
    _ data: Data,
    encoding: OTLPContentEncoding,
    maxOutputBytes: Int
  ) throws -> Data {
    switch encoding {
    case .identity:
      guard data.count <= maxOutputBytes else {
        throw OTLPRequestDecoderError.decompressedSizeLimitExceeded(max: maxOutputBytes)
      }
      return data
    case .deflate:
      return try decompressZlib(data, maxOutputBytes: maxOutputBytes)
    case .gzip:
      let member = try parseGzipMember(from: data)
      let output = try decompressZlib(member.deflatePayload, maxOutputBytes: maxOutputBytes)
      let actualCRC = CRC32.checksum(output)
      guard actualCRC == member.crc32 else {
        throw OTLPRequestDecoderError.decompressionFailed(reason: "Gzip CRC mismatch")
      }
      guard UInt32(truncatingIfNeeded: output.count) == member.isize else {
        throw OTLPRequestDecoderError.decompressionFailed(reason: "Gzip ISIZE mismatch")
      }
      return output
    }
  }

  // The per-stream `maxOutputBytes` cap below protects against zip-bomb payloads
  // that inflate to absurd sizes from a small compressed footprint. It does NOT
  // bound aggregate concurrent connections — that responsibility lives in
  // `OTLPHTTPServer` (request body limiter, max in-flight requests).
  private static func decompressZlib(_ data: Data, maxOutputBytes: Int) throws -> Data {
    if data.isEmpty { return Data() }

    let dummyDst = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    let dummySrc = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
    var stream = compression_stream(
      dst_ptr: dummyDst,
      dst_size: 0,
      src_ptr: UnsafePointer(dummySrc),
      src_size: 0,
      state: nil
    )
    defer {
      dummyDst.deallocate()
      dummySrc.deallocate()
    }
    let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
    guard status != COMPRESSION_STATUS_ERROR else {
      throw OTLPRequestDecoderError.decompressionFailed(reason: "Unable to initialize zlib stream")
    }
    defer { compression_stream_destroy(&stream) }

    return try data.withUnsafeBytes { rawBuffer in
      guard let srcBase = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return Data()
      }

      stream.src_ptr = srcBase
      stream.src_size = rawBuffer.count

      let dstSize = 64 * 1024
      let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
      defer { dstBuffer.deallocate() }

      var output = Data()
      output.reserveCapacity(min(maxOutputBytes, dstSize))

      var streamStatus = COMPRESSION_STATUS_OK
      repeat {
        // P1-14: Cooperative cancellation. The inflate loop polls
        // `Task.checkCancellation()` once per 64 KiB chunk so a calling worker
        // can be torn down without burning CPU on attacker-controlled payloads.
        try Task.checkCancellation()

        stream.dst_ptr = dstBuffer
        stream.dst_size = dstSize

        streamStatus = compression_stream_process(&stream, 0)

        let produced = dstSize - stream.dst_size
        if produced > 0 {
          if output.count + produced > maxOutputBytes {
            throw OTLPRequestDecoderError.decompressedSizeLimitExceeded(max: maxOutputBytes)
          }
          output.append(dstBuffer, count: produced)
        }

        if streamStatus == COMPRESSION_STATUS_ERROR {
          throw OTLPRequestDecoderError.decompressionFailed(reason: "Zlib decompression error")
        }
      } while streamStatus == COMPRESSION_STATUS_OK

      return output
    }
  }

  private static func parseGzipMember(from data: Data) throws -> GzipMember {
    try data.withUnsafeBytes { rawBuffer -> GzipMember in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.count >= 18 else {
        throw OTLPRequestDecoderError.malformedData(reason: "Gzip payload too small")
      }

      guard bytes[0] == 0x1F, bytes[1] == 0x8B else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip header")
      }

      guard bytes[2] == 0x08 else {
        throw OTLPRequestDecoderError.malformedData(reason: "Unsupported gzip compression method")
      }

      let flags = bytes[3]
      var index = 10

      if flags & 0x04 != 0 {
        guard index + 2 <= bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip extra field")
        }
        let xlen = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
        index += 2
        guard index + xlen <= bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip extra field length")
        }
        index += xlen
      }

      if flags & 0x08 != 0 {
        while index < bytes.count, bytes[index] != 0 {
          index += 1
        }
        guard index < bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip filename")
        }
        index += 1
      }

      if flags & 0x10 != 0 {
        while index < bytes.count, bytes[index] != 0 {
          index += 1
        }
        guard index < bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip comment")
        }
        index += 1
      }

      if flags & 0x02 != 0 {
        guard index + 2 <= bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip header CRC")
        }
        index += 2
      }

      let trailerLength = 8
      guard index <= bytes.count - trailerLength else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip trailer")
      }

      let trailerStart = bytes.count - trailerLength
      let crc32 = UInt32(bytes[trailerStart])
        | (UInt32(bytes[trailerStart + 1]) << 8)
        | (UInt32(bytes[trailerStart + 2]) << 16)
        | (UInt32(bytes[trailerStart + 3]) << 24)
      let isize = UInt32(bytes[trailerStart + 4])
        | (UInt32(bytes[trailerStart + 5]) << 8)
        | (UInt32(bytes[trailerStart + 6]) << 16)
        | (UInt32(bytes[trailerStart + 7]) << 24)

      return GzipMember(
        deflatePayload: data.subdata(in: index ..< trailerStart),
        crc32: crc32,
        isize: isize
      )
    }
  }
}

private struct GzipMember {
  let deflatePayload: Data
  let crc32: UInt32
  let isize: UInt32
}

// P1-14: CRC32 hot path. The pure-Swift table-driven implementation pinned
// a CPU for ~1.5s on a 50 MB legitimate gzip payload during stress testing.
// Apple platforms ship a SIMD-accelerated `zlib.crc32`, which the gating
// below prefers. The pure-Swift fallback is retained verbatim under the
// `#if !canImport(zlib)` branch so non-Darwin builds remain self-contained.
private enum CRC32 {
  #if canImport(zlib)
    static func checksum(_ data: Data) -> UInt32 {
      if data.isEmpty { return 0 }
      // `zlib.crc32` returns UInt (`uLong`) on macOS; the upper bits are
      // always zero for the 32-bit checksum so the truncating cast is safe.
      return data.withUnsafeBytes { rawBuffer -> UInt32 in
        guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return 0
        }
        let result = zlib.crc32(0, base, UInt32(rawBuffer.count))
        return UInt32(truncatingIfNeeded: result)
      }
    }
  #else
    static func checksum(_ data: Data) -> UInt32 {
      var crc: UInt32 = 0xFFFF_FFFF
      for byte in data {
        let index = Int((crc ^ UInt32(byte)) & 0xFF)
        crc = (crc >> 8) ^ table[index]
      }
      return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0 ..< 256).map { value in
      var crc = UInt32(value)
      for _ in 0 ..< 8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xEDB8_8320
        } else {
          crc = crc >> 1
        }
      }
      return crc
    }
  #endif
}
