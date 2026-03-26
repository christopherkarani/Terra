/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(macOS)

import Foundation
import Terra

try await Terra.start()

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
try await Task.sleep(nanoseconds: 2_000_000_000)

#else

print("TerraSample is supported on macOS.")

#endif
