/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

#if os(macOS)

import Foundation
import Terra

try await Terra.start()

try await Terra
  .agentic(name: "DemoAgent", id: "demo-agent-1") { agent in
    agent.event("agent.start")

    try await agent.infer(
      "local/demo",
      messages: [
        .init(role: "system", content: "You are a sample agent."),
        .init(role: "user", content: "Hello")
      ]
    ) {
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    try await agent.tool("search", callId: "call-1") {
      try await Task.sleep(nanoseconds: 20_000_000)
    }

    agent.event("agent.end")
  }

// Give periodic metrics export a moment to run in this sample.
try await Task.sleep(nanoseconds: 2_000_000_000)

#else

print("TerraSample is supported on macOS.")

#endif
