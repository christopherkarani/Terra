import ArgumentParser
import Foundation

struct TraceDoctorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Checklist for common trace setup issues."
  )

  func run() async throws {
    print("Trace doctor checklist")
    print("- Simulator endpoint: http://localhost:4318/v1/traces")
    print("- Device endpoint: run `terra trace serve --bind-all --port 4318`, then use http://<mac_lan_ip>:4318/v1/traces")
    print("- No spans arriving: confirm the app sets otlpTracesEndpoint, ATS allows http, Local Network permission granted, and Mac + device share the same LAN.")
  }
}
