import ArgumentParser
import Foundation

enum TracePrintFormat: String, ExpressibleByArgument {
  case tree
  case json
}

struct TracePrintCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "print",
    abstract: "Render captured traces from a file (v1.1 scaffold)."
  )

  @Option(name: .customLong("otlp-file"), help: "Path to an OTLP protobuf file.")
  var otlpFile: String?

  @Option(name: .customLong("jsonl"), help: "Path to a JSONL file.")
  var jsonlFile: String?

  @Option(help: "Output format: tree or json.")
  var format: TracePrintFormat = .tree

  func validate() throws {
    if (otlpFile == nil) == (jsonlFile == nil) {
      throw ValidationError("Provide exactly one input: --otlp-file or --jsonl.")
    }
  }

  func run() async throws {
    print("terra trace print is not implemented yet. Parsed input format: \(format.rawValue).")
  }
}
