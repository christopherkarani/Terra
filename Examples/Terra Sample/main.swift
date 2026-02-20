/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(macOS)

import Foundation
import Terra

@main
struct TerraSample {
  static func main() async throws {
    // One-call OpenTelemetry wiring (OTLP/HTTP + on-device persistence + Signposts).
    try Terra.installOpenTelemetry(
      .init(
        enableLogs: false,
        metricsExportInterval: 1,
        persistence: .init(storageURL: Terra.defaultPersistenceStorageURL(), performancePreset: .default)
      )
    )

    // Privacy-safe defaults (no prompt/output/tool-args capture).
    Terra.install(.init(privacy: .default))

    let agent = Terra.Agent(name: "DemoAgent")

    try await Terra.withAgentInvocationSpan(agent: agent) { scope in
      scope.addEvent("agent.start")

      try await Terra.withInferenceSpan(.init(model: "local/demo", prompt: "Hello")) { _ in
        try await Task.sleep(nanoseconds: 50_000_000)
      }

      try await Terra.withToolExecutionSpan(tool: .init(name: "search"), call: .init(id: "call-1")) { _ in
        try await Task.sleep(nanoseconds: 20_000_000)
      }

      scope.addEvent("agent.end")
    }

    // Give periodic metrics export a moment to run in this sample.
    try await Task.sleep(nanoseconds: 2_000_000_000)
  }
}

#else

@main
struct TerraSample {
  static func main() {
    print("TerraSample is supported on macOS.")
  }
}

#endif
