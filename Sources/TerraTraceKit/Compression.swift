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
      #if canImport(zlib)
      return try decompressGzip(data, maxOutputBytes: maxOutputBytes)
      #else
      let deflatePayload = try extractGzipDeflatePayload(from: data)
      return try decompressZlib(deflatePayload, maxOutputBytes: maxOutputBytes)
      #endif
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

  private static func extractGzipDeflatePayload(from data: Data) throws -> Data {
    try data.withUnsafeBytes { rawBuffer -> Data in
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

      return data.subdata(in: index..<(bytes.count - trailerLength))
    }
  }

  #if canImport(zlib)
  private static func decompressGzip(_ data: Data, maxOutputBytes: Int) throws -> Data {
    if data.isEmpty { return Data() }

    var stream = z_stream()
    let initResult = inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard initResult == Z_OK else {
      throw OTLPRequestDecoderError.decompressionFailed(reason: "Unable to initialize gzip stream")
    }
    defer { inflateEnd(&stream) }

    let chunkSize = 64 * 1024
    var output = Data()
    output.reserveCapacity(min(maxOutputBytes, chunkSize))

    return try data.withUnsafeBytes { rawBuffer in
      guard let inputBase = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return Data()
      }

      stream.next_in = UnsafeMutablePointer(mutating: inputBase)
      stream.avail_in = uInt(rawBuffer.count)

      var outBuffer = [UInt8](repeating: 0, count: chunkSize)
      while true {
        let result = outBuffer.withUnsafeMutableBytes { outRawBuffer -> Int32 in
          guard let outBase = outRawBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return Z_BUF_ERROR
          }
          stream.next_out = outBase
          stream.avail_out = uInt(chunkSize)
          return inflate(&stream, Z_NO_FLUSH)
        }

        let produced = chunkSize - Int(stream.avail_out)
        if produced > 0 {
          if output.count + produced > maxOutputBytes {
            throw OTLPRequestDecoderError.decompressedSizeLimitExceeded(max: maxOutputBytes)
          }
          output.append(outBuffer, count: produced)
        }

        if result == Z_STREAM_END {
          break
        }
        if result != Z_OK {
          throw OTLPRequestDecoderError.decompressionFailed(reason: "Gzip decompression error (\(result))")
        }
      }

      return output
    }
  }
  #endif
}
