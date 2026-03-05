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
    try await Terra.start()

    try await Terra
      .agent("DemoAgent")
      .run { trace in
        trace.event("agent.start")

        try await Terra.infer(Terra.ModelID("local/demo"), prompt: "Hello").run {
          try await Task.sleep(nanoseconds: 50_000_000)
        }

        try await Terra.tool("search", callID: Terra.ToolCallID("call-1")).run {
          try await Task.sleep(nanoseconds: 20_000_000)
        }

        trace.event("agent.end")
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
