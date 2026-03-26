import Foundation
import Testing

@Test("Public docs stay on canonical APIs")
func publicDocsStayOnCanonicalAPIs() throws {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let files = [
    "README.md",
    "Docs/cookbook.md",
    "Docs/integrations.md",
    "Sources/TerraAutoInstrument/Terra.docc/Canonical-API.md",
    "Sources/TerraAutoInstrument/Terra.docc/CoreML-Integration.md",
    "Sources/TerraAutoInstrument/Terra.docc/FoundationModels.md",
    "Sources/TerraAutoInstrument/Terra.docc/Metadata-Builder.md",
    "Sources/TerraAutoInstrument/Terra.docc/Quickstart-90s.md",
    "Sources/TerraAutoInstrument/Terra.docc/TerraCore.md",
    "Sources/TerraAutoInstrument/Terra.docc/Typed-IDs.md",
    "Examples/Terra Sample/RecipeSnippets.swift",
  ]

  let bannedPatterns = [
    ".attr(",
    ".provider(",
    ".execute {",
    ".includeContent()",
    "trace.attribute(",
    "Terra.ModelID(",
    "Terra.ToolCallID(",
    "callID:",
  ]

  for relativePath in files {
    let source = try String(contentsOf: repoRoot.appendingPathComponent(relativePath))
    for pattern in bannedPatterns {
      #expect(
        !source.contains(pattern),
        "Found \(pattern) in \(relativePath)"
      )
    }
  }
}
