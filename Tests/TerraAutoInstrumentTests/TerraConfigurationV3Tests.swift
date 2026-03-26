import Foundation
import Testing
@testable import Terra
@testable import TerraCore

@Suite(.serialized) struct TerraConfigurationV3Tests {

  @Test func quickstartDefaults() {
    let config = Terra.Configuration(preset: .quickstart)
    #expect(config.privacy == .redacted)
    #expect(config.features.contains(.coreML))
    #expect(config.features.contains(.http))
    #expect(config.features.contains(.sessions))
    #expect(config.features.contains(.signposts))
    #expect(!config.features.contains(.logs))
    if case .localDashboard = config.destination { } else { Issue.record("Expected .localDashboard") }
    if case .off = config.persistence { } else { Issue.record("Expected .off persistence") }
    #expect(config.profiling.isEmpty)
  }

  @Test func productionPresetEnablesPersistence() {
    let config = Terra.Configuration(preset: .production)
    if case .balanced = config.persistence { } else { Issue.record("Expected .balanced persistence") }
    #expect(config.profiling.isEmpty)
    #expect(!config.features.contains(.logs))
  }

  @Test func diagnosticsPresetEnablesAll() {
    let config = Terra.Configuration(preset: .diagnostics)
    #expect(config.profiling == .standard)
    if case .balanced = config.persistence { } else { Issue.record("Expected .balanced persistence") }
    #expect(config.features.contains(.logs))
    #expect(config.features.contains(.signposts))
    #expect(config.features.contains(.sessions))
  }

  @Test func destinationLocalDashboard() {
    let config = Terra.Configuration(preset: .quickstart)
    if case .localDashboard = config.destination { } else { Issue.record("Expected .localDashboard") }
  }

  @Test func destinationCustomEndpoint() {
    var config = Terra.Configuration(preset: .quickstart)
    config.destination = .endpoint(URL(string: "http://my-collector:4318")!)
    if case .endpoint(let url) = config.destination {
      #expect(url.host == "my-collector")
    } else {
      Issue.record("Expected .endpoint")
    }
  }

  @Test func featuresAreCustomizable() {
    var config = Terra.Configuration(preset: .quickstart)
    config.features = [.coreML]
    #expect(config.features.contains(.coreML))
    #expect(!config.features.contains(.http))
  }
}
