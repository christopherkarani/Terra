/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(macOS)

import Foundation
import Terra

private func environmentValue(_ name: String) -> String? {
  guard let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
  else {
    return nil
  }
  return value
}

let smokeMode = environmentValue("TERRA_SMOKE_ENDPOINT") != nil

if let endpointString = environmentValue("TERRA_SMOKE_ENDPOINT"),
   let endpoint = URL(string: endpointString),
   let ingestKey = environmentValue("TERRA_SMOKE_INGEST_KEY"),
   let environmentName = environmentValue("TERRA_SMOKE_ENVIRONMENT")
{
  let processName = ProcessInfo.processInfo.processName
  let bundleIdentifier = Bundle.main.bundleIdentifier ?? "<nil>"
  print("TerraSample smoke: starting production ingest")
  print("TerraSample smoke: process=\(processName) bundle=\(bundleIdentifier) environment=\(environmentName)")
  var config = Terra.Configuration(preset: .production)
  config.destination = .endpoint(endpoint)
  config.persistence = .off
  config.productionIngest = .init(
    environmentName: environmentName,
    ingestKey: ingestKey,
    installationID: environmentValue("TERRA_SMOKE_INSTALLATION_ID")
  )
  try await Terra.start(config)
} else {
  try await Terra.start()
}

try await Terra.workflow(name: "DemoAgent", id: "demo-agent-1") { workflow in
  workflow.event("workflow.start")

  _ = try await workflow.infer(
    "local/demo",
    messages: [
      Terra.ChatMessage(role: "system", content: "You are a sample agent."),
      Terra.ChatMessage(role: "user", content: "Hello")
    ]
  ) {
    try await Task.sleep(nanoseconds: 50_000_000)
  }

  _ = try await workflow.tool("search", callId: "call-1") {
    try await Task.sleep(nanoseconds: 20_000_000)
  }

  workflow.event("workflow.end")
}

// Give periodic metrics export a moment to run in this sample.
if smokeMode { print("TerraSample smoke: workflow complete, waiting for export") }
try await Task.sleep(nanoseconds: 2_000_000_000)
if smokeMode { print("TerraSample smoke: shutting down") }
await Terra.shutdown()
if smokeMode { print("TerraSample smoke: shutdown complete") }

#else

print("TerraSample is supported on macOS.")

#endif
