#if os(macOS)
import Foundation
import OpenTelemetryApi
import TerraSystemProfiler

package struct CostModelEntry: Sendable, Codable, Hashable {
  package let name: String
  package let type: String
  package let gFlopCnt: Double
  package let gflops: Double
  package let gbps: Double
  package let runtimeMs: Double
  package let isMemoryBound: Bool
  package let workUnitEfficiency: Double
}

public struct EspressoLogSummary: Sendable, TelemetryAttributeConvertible {
  public let totalGFlops: Double
  public let memoryBoundCount: Int
  public let computeBoundCount: Int
  public let averageWorkUnitEfficiency: Double
  package let entries: [CostModelEntry]

  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.espresso.total_gflops": .double(totalGFlops),
      "terra.espresso.memory_bound_ops": .int(memoryBoundCount),
      "terra.espresso.compute_bound_ops": .int(computeBoundCount),
      "terra.espresso.avg_work_unit_efficiency": .double(averageWorkUnitEfficiency),
    ]
  }
}

enum EspressoLogParser {
  // Sample line format:
  // CostModelFeature: name=conv1 type=convolution gFlopCnt=0.12 gflops=45.3 gbps=12.1 runtime_ms=2.65 is_memory_bound=1 work_unit_efficiency=0.85
  private static let pattern: NSRegularExpression = {
    // swiftlint:disable:next force_try
    try! NSRegularExpression(
      pattern: #"CostModelFeature:.*?name=(\S+).*?type=(\S+).*?gFlopCnt=([\d.]+).*?gflops=([\d.]+).*?gbps=([\d.]+).*?runtime_ms=([\d.]+).*?is_memory_bound=(\d+).*?work_unit_efficiency=([\d.]+)"#,
      options: []
    )
  }()

  static func parse(_ output: String) -> [CostModelEntry] {
    output.components(separatedBy: "\n").compactMap { line in
      let nsLine = line as NSString
      guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
            match.numberOfRanges == 9
      else { return nil }

      func str(_ index: Int) -> String {
        nsLine.substring(with: match.range(at: index))
      }

      return CostModelEntry(
        name: str(1),
        type: str(2),
        gFlopCnt: Double(str(3)) ?? 0,
        gflops: Double(str(4)) ?? 0,
        gbps: Double(str(5)) ?? 0,
        runtimeMs: Double(str(6)) ?? 0,
        isMemoryBound: str(7) == "1",
        workUnitEfficiency: Double(str(8)) ?? 0
      )
    }
  }

  static func summarize(_ entries: [CostModelEntry]) -> EspressoLogSummary {
    let totalGFlops = entries.reduce(0) { $0 + $1.gFlopCnt }
    let memoryBound = entries.filter(\.isMemoryBound).count
    let computeBound = entries.count - memoryBound
    let avgEfficiency = entries.isEmpty ? 0 : entries.reduce(0) { $0 + $1.workUnitEfficiency } / Double(entries.count)

    return EspressoLogSummary(
      totalGFlops: totalGFlops,
      memoryBoundCount: memoryBound,
      computeBoundCount: computeBound,
      averageWorkUnitEfficiency: avgEfficiency,
      entries: entries
    )
  }
}
#endif
