import Testing
import TerraCore
import TerraTracedMacro

private struct MinimalImportSmokeType {
  @Traced(model: "smoke-model")
  func generate(prompt: String) async throws -> String {
    return prompt
  }

  @Traced(model: Terra.ModelID("legacy-model"))
  func legacyGenerate(prompt: String) async throws -> String {
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

  @Traced(tool: "smoke-tool", callID: Terra.ToolCallID("call-2"))
  func legacyRun(input: String) async throws -> String {
    return input
  }

  @Traced(tool: "smoke-tool")
  func runWithOptionalCallId(input: String, callId: String?) async throws -> String {
    return input
  }

  @Traced(tool: "smoke-tool")
  func runWithOptionalLegacyCallId(input: String, callId: Terra.ToolCallID?) async throws -> String {
    return input
  }
}

@Test("Macro expansion compiles with only TerraCore + TerraTracedMacro imports")
func macroExpansionCompilesWithMinimalImports() async throws {
  let value = try await MinimalImportSmokeType().generate(prompt: "hello")
  #expect(value == "hello")

  let legacyValue = try await MinimalImportSmokeType().legacyGenerate(prompt: "hello")
  #expect(legacyValue == "hello")
}

@Test("Tool macro expansion compiles with string call identifiers")
func toolMacroExpansionCompiles() async throws {
  let value = try await ToolMacroSmokeType().run(input: "hello")
  #expect(value == "hello")

  let valueWithCallId = try await ToolMacroSmokeType().runWithCallId(input: "hello", callId: "call-1")
  #expect(valueWithCallId == "hello")

  let legacyValue = try await ToolMacroSmokeType().legacyRun(input: "hello")
  #expect(legacyValue == "hello")

  let optionalValue = try await ToolMacroSmokeType().runWithOptionalCallId(input: "hello", callId: nil)
  #expect(optionalValue == "hello")

  let optionalLegacyValue = try await ToolMacroSmokeType().runWithOptionalLegacyCallId(input: "hello", callId: nil)
  #expect(optionalLegacyValue == "hello")
}
