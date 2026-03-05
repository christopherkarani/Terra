import Testing
import TerraCore
import TerraTracedMacro

private struct MinimalImportSmokeType {
  @Traced(model: Terra.ModelID("smoke-model"))
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
  func runWithCallID(input: String, callID: String) async throws -> String {
    return input
  }
}

@Test("Macro expansion compiles with only TerraCore + TerraTracedMacro imports")
func macroExpansionCompilesWithMinimalImports() async throws {
  let value = try await MinimalImportSmokeType().generate(prompt: "hello")
  #expect(value == "hello")
}

@Test("Tool macro expansion compiles with typed ToolCallID bridging")
func toolMacroExpansionCompiles() async throws {
  let value = try await ToolMacroSmokeType().run(input: "hello")
  #expect(value == "hello")

  let valueWithCallID = try await ToolMacroSmokeType().runWithCallID(input: "hello", callID: "call-1")
  #expect(valueWithCallID == "hello")
}
