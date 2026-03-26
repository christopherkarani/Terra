import Testing
import TerraCore
import TerraTracedMacro

@Suite("TracedMacro import smoke", .serialized)
struct TracedMacroImportSmokeTests {
private struct MinimalImportSmokeType {
  @Traced(model: "smoke-model")
  func generate(prompt: String) async throws -> String {
    return prompt
  }
}

private struct ToolMacroSmokeType {
  @Traced(tool: "smoke-tool")
  func run(input: String) async throws -> String {
    return input
  }

  @Traced(tool: "smoke-tool")
  func runWithCallId(input: String, callId: String) async throws -> String {
    return input
  }

  @Traced(tool: "smoke-tool")
  func runWithOptionalCallId(input: String, callId: String?) async throws -> String {
    return input
  }
}

@Test("Macro expansion compiles with only TerraCore + TerraTracedMacro imports")
func macroExpansionCompilesWithMinimalImports() async throws {
  let value = try await MinimalImportSmokeType().generate(prompt: "hello")
  #expect(value == "hello")
}

@Test("Tool macro expansion compiles with string call identifiers")
func toolMacroExpansionCompiles() async throws {
  let value = try await ToolMacroSmokeType().run(input: "hello")
  #expect(value == "hello")

  let valueWithCallId = try await ToolMacroSmokeType().runWithCallId(input: "hello", callId: "call-1")
  #expect(valueWithCallId == "hello")

  let optionalValue = try await ToolMacroSmokeType().runWithOptionalCallId(input: "hello", callId: nil)
  #expect(optionalValue == "hello")
}
}
