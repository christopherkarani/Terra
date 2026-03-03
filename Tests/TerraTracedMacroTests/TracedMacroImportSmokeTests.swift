import Testing
import TerraCore
import TerraTracedMacro

private struct MinimalImportSmokeType {
  @Traced(model: "smoke-model")
  func generate(prompt: String) async throws -> String {
    return prompt
  }
}

@Test("Macro expansion compiles with only TerraCore + TerraTracedMacro imports")
func macroExpansionCompilesWithMinimalImports() async throws {
  let value = try await MinimalImportSmokeType().generate(prompt: "hello")
  #expect(value == "hello")
}
