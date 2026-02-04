import ArgumentParser
import Dispatch
import Foundation
import TerraTraceKit

enum TraceServeFormat: String, ExpressibleByArgument {
  case stream
  case tree
}

struct TraceServeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "serve",
    abstract: "Start an OTLP/HTTP trace receiver and live renderer."
  )

  @Option(help: "Bind host. Default is 127.0.0.1.")
  var host: String = "127.0.0.1"

  @Option(help: "Bind port. Default is 4318.")
  var port: Int = 4318

  @Flag(name: .customLong("bind-all"), help: "Bind to 0.0.0.0 for device access.")
  var bindAll: Bool = false

  @Option(help: "Output format: stream or tree.")
  var format: TraceServeFormat = .stream

  @Option(name: .customLong("print-every"), help: "Tree refresh cadence in seconds (tree format only).")
  var printEvery: Double = 2

  @Option(
    name: .customLong("filter"),
    parsing: .upToNextOption,
    help: "Filter output. Use --filter name=<prefix> or --filter trace=<traceId>."
  )
  var filterOptions: [TraceFilterOption] = []

  func validate() throws {
    if port <= 0 || port > 65535 {
      throw ValidationError("Port must be between 1 and 65535.")
    }
    if printEvery <= 0 {
      throw ValidationError("Print cadence must be greater than 0 seconds.")
    }
  }

  func run() async throws {
    let resolvedHost = bindAll ? "0.0.0.0" : host
    let filters = try TraceFilterSelection(options: filterOptions)
    let filter = TraceFilter(traceID: filters.traceID, namePrefix: filters.namePrefix)

    let store = TraceStore()
    let streamRenderer = StreamRenderer(filter: filter)
    let treeRenderer = TreeRenderer(filter: filter)

    let server = OTLPHTTPServer(
      host: resolvedHost,
      port: UInt16(port),
      traceStore: store
    ) { spans in
      guard format == .stream else {
        return
      }

      let lines = streamRenderer.render(spans: spans)
      for line in lines {
        print(line)
      }
    }

    try server.start()
    printStartupInstructions(host: resolvedHost, port: port, bindAll: bindAll)

    if format == .tree {
      startPeriodicTreeRendering(store: store, renderer: treeRenderer, every: printEvery)
    }

    dispatchMain()
  }
}

private func printStartupInstructions(host: String, port: Int, bindAll: Bool) {
  print("Listening on http://\(host):\(port)/v1/traces")
  print("")
  print("Simulator:")
  print("  otlpTracesEndpoint = http://localhost:\(port)/v1/traces")
  print("")
  print("Device:")
  if !bindAll {
    print("  Run with --bind-all (host 0.0.0.0) so devices can reach this Mac.")
  }
  print("  otlpTracesEndpoint = http://<mac_lan_ip>:\(port)/v1/traces")
  print("  Ensure ATS allows http and Local Network permission is granted.")
}

private func startPeriodicTreeRendering(
  store: TraceStore,
  renderer: TreeRenderer,
  every seconds: Double
) {
  let interval = UInt64(seconds * 1_000_000_000)
  Task.detached {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: interval)
      let snapshot = await store.snapshot()
      let output = renderer.render(snapshot: snapshot)
      guard !output.isEmpty else { continue }
      print(output)
    }
  }
}
