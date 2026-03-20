import Foundation

enum PowerMetricsParser {
  // powermetrics output contains lines like:
  // CPU Power: 1234 mW
  // GPU Power: 567 mW
  // ANE Power: 89 mW
  // Combined Power (CPU + GPU + ANE): 1890 mW

  static func parse(_ output: String) -> PowerSample? {
    var cpu: Double?
    var gpu: Double?
    var ane: Double?
    var package: Double?

    for line in output.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("CPU Power:") {
        cpu = extractMilliwatts(from: trimmed)
      } else if trimmed.hasPrefix("GPU Power:") {
        gpu = extractMilliwatts(from: trimmed)
      } else if trimmed.hasPrefix("ANE Power:") {
        ane = extractMilliwatts(from: trimmed)
      } else if trimmed.hasPrefix("Combined Power") || trimmed.hasPrefix("Package Power") {
        package = extractMilliwatts(from: trimmed)
      }
    }

    guard cpu != nil || gpu != nil || ane != nil else { return nil }

    return PowerSample(
      cpuWatts: (cpu ?? 0) / 1000,
      gpuWatts: (gpu ?? 0) / 1000,
      aneWatts: (ane ?? 0) / 1000,
      packageWatts: (package ?? 0) / 1000
    )
  }

  private static func extractMilliwatts(from line: String) -> Double? {
    // Extract numeric value before "mW"
    let components = line.components(separatedBy: ":")
    guard components.count >= 2 else { return nil }
    let valuePart = components[1].trimmingCharacters(in: .whitespaces)
    // Remove " mW" suffix
    let numericString = valuePart
      .replacingOccurrences(of: " mW", with: "")
      .trimmingCharacters(in: .whitespaces)
    return Double(numericString)
  }
}
