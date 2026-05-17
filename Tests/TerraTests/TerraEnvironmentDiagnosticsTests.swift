import Testing
@testable import TerraCore

@Suite("Terra Environment Diagnostics", .serialized)
struct TerraEnvironmentDiagnosticsTests {
  @Test("diagnoseEnvironment returns structured runtime and platform probes")
  func diagnoseEnvironmentReturnsStructuredProbes() {
    let support = TerraTestSupport()
    defer { support.tearDown() }
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    let report = Terra.diagnoseEnvironment()

    #expect(report.tracing.tracerProvider == .available)
    #expect(report.backend.swiftOpenTelemetry == .available)
    #expect(report.backend.activeBackend == "swift-opentelemetry")
    #expect(!report.platform.osName.isEmpty)
    #expect(!report.platform.architecture.isEmpty)
    #expect(report.tooling.swiftToolsVersion == "5.9")
    #expect(report.nativeLibrary.moduleName == "CTerraBridge")
    #expect(report.ane.probeSource == "CTerraANEBridge")
    #expect(report.recommendedFixes.allSatisfy { !$0.code.isEmpty && !$0.message.isEmpty })
  }

  @Test("diagnoseEnvironment reports provider fixes when tracing is not installed")
  func diagnoseEnvironmentReportsProviderFixesWhenTracingIsMissing() {
    let report = Terra.diagnoseEnvironment()

    if report.tracing.tracerProvider == .unavailable {
      #expect(report.recommendedFixes.contains { $0.code == "INSTALL_TRACER_PROVIDER" })
    }
  }
}
