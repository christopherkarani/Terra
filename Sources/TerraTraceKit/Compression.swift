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

struct OTLPDecompressor {
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
      let member = try extractGzipMember(from: data)
      #if canImport(zlib)
      let decompressed: Data
      do {
        decompressed = try decompressRawDeflate(member.deflatePayload, maxOutputBytes: maxOutputBytes)
      } catch OTLPRequestDecoderError.decompressionFailed(reason: _) {
        // Backward-compatible fallback for legacy gzip writers that wrapped DEFLATE with zlib headers.
        decompressed = try decompressZlib(member.deflatePayload, maxOutputBytes: maxOutputBytes)
      }
      #else
      let decompressed = try decompressZlib(member.deflatePayload, maxOutputBytes: maxOutputBytes)
      #endif
      guard CRC32.checksum(decompressed) == member.crc32 else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip trailer checksum")
      }
      guard UInt32(truncatingIfNeeded: decompressed.count) == member.isize else {
        throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip trailer size")
      }
      return decompressed
    }
  }

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

  #if canImport(zlib)
  private static func decompressRawDeflate(_ data: Data, maxOutputBytes: Int) throws -> Data {
    if data.isEmpty { return Data() }

    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      -MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else {
      throw OTLPRequestDecoderError.decompressionFailed(reason: "Unable to initialize raw deflate stream")
    }
    defer {
      inflateEnd(&stream)
    }

    var output = Data()
    output.reserveCapacity(min(maxOutputBytes, 64 * 1024))

    return try data.withUnsafeBytes { rawBuffer -> Data in
      guard let srcBase = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
        return Data()
      }

      stream.next_in = UnsafeMutablePointer<Bytef>(mutating: srcBase)
      stream.avail_in = uInt(rawBuffer.count)

      let chunkSize = 64 * 1024
      var chunk = [UInt8](repeating: 0, count: chunkSize)
      var streamStatus: Int32 = Z_OK

      repeat {
        let produced = chunk.withUnsafeMutableBytes { rawOutBuffer -> Int in
          stream.next_out = rawOutBuffer.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(rawOutBuffer.count)
          streamStatus = inflate(&stream, Z_NO_FLUSH)
          return rawOutBuffer.count - Int(stream.avail_out)
        }
        if produced > 0 {
          if output.count + produced > maxOutputBytes {
            throw OTLPRequestDecoderError.decompressedSizeLimitExceeded(max: maxOutputBytes)
          }
          output.append(chunk, count: produced)
        }

        if streamStatus == Z_STREAM_END {
          break
        }
        if streamStatus != Z_OK {
          let code = streamStatus
          throw OTLPRequestDecoderError.decompressionFailed(reason: "Raw deflate decompression error (\(code))")
        }
      } while true

      return output
    }
  }
  #endif

  private static func extractGzipMember(from data: Data) throws -> GzipMember {
    try data.withUnsafeBytes { rawBuffer -> GzipMember in
      let bytes = rawBuffer.bindMemory(to: UInt8.self)
      guard bytes.count >= 18 else {
        throw OTLPRequestDecoderError.malformedData(reason: "Gzip payload too small")
      }

      guard bytes[0] == 0x1f, bytes[1] == 0x8b else {
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
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else {
          throw OTLPRequestDecoderError.malformedData(reason: "Invalid gzip filename")
        }
        index += 1
      }

      if flags & 0x10 != 0 {
        while index < bytes.count, bytes[index] != 0 { index += 1 }
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
      let crc32 =
        UInt32(bytes[trailerStart])
        | (UInt32(bytes[trailerStart + 1]) << 8)
        | (UInt32(bytes[trailerStart + 2]) << 16)
        | (UInt32(bytes[trailerStart + 3]) << 24)
      let isize =
        UInt32(bytes[trailerStart + 4])
        | (UInt32(bytes[trailerStart + 5]) << 8)
        | (UInt32(bytes[trailerStart + 6]) << 16)
        | (UInt32(bytes[trailerStart + 7]) << 24)

      return GzipMember(
        deflatePayload: data.subdata(in: index..<trailerStart),
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

private enum CRC32 {
  static func checksum(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ table[index]
    }
    return crc ^ 0xffff_ffff
  }

  private static let table: [UInt32] = {
    (0..<256).map { value in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb8_8320
        } else {
          crc = crc >> 1
        }
      }
      return crc
    }
  }()
}
