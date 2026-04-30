import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// Result of loading traces, including any per-file failures.
public struct TraceLoadResult {
  public let traces: [Trace]
  public let failures: [(file: URL, error: Error)]
  public let loadedFileCount: Int
  public let totalFileCount: Int
}

/// Loads traces from persisted files using a locator, reader, and decoder.
public struct TraceLoader {
  public let locator: TraceFileLocator
  public let reader: TraceFileReader
  public let decoder: TraceDecoder

  /// Creates a loader with injectable persistence components.
  public init(
    locator: TraceFileLocator = TraceFileLocator(),
    reader: TraceFileReader = TraceFileReader(),
    decoder: TraceDecoder = TraceDecoder()
  ) {
    self.locator = locator
    self.reader = reader
    self.decoder = decoder
  }

  /// Loads and groups spans into trace models, reporting per-file failures.
  public func loadTracesWithFailures(maxFiles: Int? = nil) throws -> TraceLoadResult {
    let files = try locator.listTraceFiles()
    let filesToProcess: [TraceFileReference]
    if let maxFiles {
      let boundedMax = max(0, maxFiles)
      filesToProcess = Array(files.suffix(boundedMax))
    } else {
      filesToProcess = files
    }

    var traces = [Trace]()
    var failures = [(file: URL, error: Error)]()

    for file in filesToProcess {
      let spans: [SpanData]
      do {
        let data = try reader.read(file: file)
        spans = try decoder.decodeSpans(from: data)
      } catch {
        failures.append((file: file.url, error: error))
        continue
      }

      if spans.isEmpty {
        continue
      }

      let grouped = Dictionary(grouping: spans, by: { $0.traceId })
      for (traceId, groupSpans) in grouped {
        let id = "\(file.fileName)-\(traceId.hexString)"
        do {
          let trace = try Trace(fileName: id, spans: groupSpans)
          traces.append(trace)
        } catch {
          failures.append((file: file.url, error: error))
        }
      }
    }

    let coalescedTraces = coalesceTracesByTraceID(traces)

    return TraceLoadResult(
      traces: coalescedTraces,
      failures: failures,
      loadedFileCount: filesToProcess.count,
      totalFileCount: files.count
    )
  }

  /// Loads and groups spans into trace models (legacy convenience; discards failures).
  public func loadTraces() throws -> [Trace] {
    try loadTracesWithFailures().traces
  }

  private func coalesceTracesByTraceID(_ traces: [Trace]) -> [Trace] {
    guard traces.count > 1 else { return traces }

    let grouped = Dictionary(grouping: traces, by: { $0.traceID.hexString })
    var coalesced: [Trace] = []
    coalesced.reserveCapacity(grouped.count)

    for (traceID, group) in grouped {
      guard group.count > 1 else {
        if let single = group.first {
          coalesced.append(single)
        }
        continue
      }

      let mergedSpans = deduplicatedSpans(from: group)
      guard !mergedSpans.isEmpty else {
        if let fallback = group.max(by: traceSortNewestFirst) {
          coalesced.append(fallback)
        }
        continue
      }

      let mergedStart = mergedSpans.map(\.startTime).min()
        ?? group.map(\.startTime).min()
        ?? Date()
      let fileName = coalescedTraceFileName(startTime: mergedStart, traceID: traceID)

      do {
        let mergedTrace = try Trace(fileName: fileName, spans: mergedSpans)
        coalesced.append(mergedTrace)
      } catch {
        if let fallback = group.max(by: traceSortNewestFirst) {
          coalesced.append(fallback)
        }
      }
    }

    return coalesced.sorted(by: traceSortNewestFirst)
  }

  private func deduplicatedSpans(from traces: [Trace]) -> [SpanData] {
    var spanByID: [String: SpanData] = [:]
    spanByID.reserveCapacity(traces.reduce(0) { $0 + $1.spans.count })

    let allSpans = traces
      .flatMap(\.spans)
      .sorted(by: spanSortAscending(_:_:))

    for span in allSpans {
      let key = span.spanId.hexString
      if let existing = spanByID[key] {
        spanByID[key] = preferredSpan(existing: existing, candidate: span)
      } else {
        spanByID[key] = span
      }
    }

    return spanByID.values.sorted(by: spanSortAscending(_:_:))
  }

  private func preferredSpan(existing: SpanData, candidate: SpanData) -> SpanData {
    if candidate.hasEnded != existing.hasEnded {
      return candidate.hasEnded ? candidate : existing
    }
    if candidate.endTime != existing.endTime {
      return candidate.endTime > existing.endTime ? candidate : existing
    }
    if candidate.attributes.count != existing.attributes.count {
      return candidate.attributes.count > existing.attributes.count ? candidate : existing
    }
    if candidate.events.count != existing.events.count {
      return candidate.events.count > existing.events.count ? candidate : existing
    }
    if candidate.links.count != existing.links.count {
      return candidate.links.count > existing.links.count ? candidate : existing
    }
    return existing
  }

  private func coalescedTraceFileName(startTime: Date, traceID: String) -> String {
    let millis = Int64(max(0, startTime.timeIntervalSinceReferenceDate * 1000))
    return "\(millis)-\(traceID)"
  }

  private func traceSortNewestFirst(_ lhs: Trace, _ rhs: Trace) -> Bool {
    if lhs.startTime != rhs.startTime {
      return lhs.startTime > rhs.startTime
    }
    if lhs.endTime != rhs.endTime {
      return lhs.endTime > rhs.endTime
    }
    if lhs.fileTimestamp != rhs.fileTimestamp {
      return lhs.fileTimestamp > rhs.fileTimestamp
    }
    if lhs.id != rhs.id {
      return lhs.id < rhs.id
    }
    return lhs.traceID.hexString < rhs.traceID.hexString
  }

  private func spanSortAscending(_ lhs: SpanData, _ rhs: SpanData) -> Bool {
    if lhs.startTime != rhs.startTime {
      return lhs.startTime < rhs.startTime
    }
    if lhs.endTime != rhs.endTime {
      return lhs.endTime < rhs.endTime
    }
    return lhs.spanId.hexString < rhs.spanId.hexString
  }
}
