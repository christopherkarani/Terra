import ArgumentParser

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct TerraCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "terra",
    abstract: "Terra developer tools.",
    subcommands: [TraceCommand.self]
  )
}

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct TraceCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "trace",
    abstract: "Trace utilities for OTLP/HTTP.",
    subcommands: [TraceServeCommand.self, TracePrintCommand.self, TraceDoctorCommand.self]
  )
}
