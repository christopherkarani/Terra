import Foundation
import Testing

@Suite("Documentation lint", .serialized)
struct DocumentationLintTests {
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
    "Sources/TerraAutoInstrument/Terra.docc/API-Reference.md",
    "Sources/TerraAutoInstrument/Terra.docc/CoreML-Integration.md",
    "Sources/TerraAutoInstrument/Terra.docc/FoundationModels.md",
    "Sources/TerraAutoInstrument/Terra.docc/Metadata-Builder.md",
    "Sources/TerraAutoInstrument/Terra.docc/Profiler-Integration.md",
    "Sources/TerraAutoInstrument/Terra.docc/Quickstart-90s.md",
    "Sources/TerraAutoInstrument/Terra.docc/TerraCore.md",
    "Sources/TerraAutoInstrument/Terra.docc/Terra.md",
    "Sources/TerraAutoInstrument/Terra.docc/TerraError-Model.md",
    "Sources/TerraAutoInstrument/Terra.docc/TelemetryEngine-Injection.md",
    "Sources/TerraAutoInstrument/Terra.docc/Typed-IDs.md",
    "Examples/Terra Sample/RecipeSnippets.swift",
  ]

  let bannedPatterns = [
    ".attr(",
    ".provider(",
    ".execute {",
    ".includeContent()",
    "trace.attribute(",
    "Terra.trace(",
    "Terra.agentic(",
    "Terra.loop(",
    "TraceHandle",
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

@Test("Migration guide points legacy roots to workflow-first replacements")
func migrationGuidePointsLegacyRootsToWorkflowFirstReplacements() throws {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let source = try String(contentsOf: repoRoot.appendingPathComponent("Docs/migration.md"))

  #expect(source.contains("| `Terra.trace(name:id:_:)` | `Terra.workflow(name:id:_:)` |"))
  #expect(source.contains("| `Terra.loop(name:id:messages:_:)` | `Terra.workflow(name:id:messages:_:)` |"))
  #expect(source.contains("| `Terra.agentic(name:id:_:)` | `Terra.workflow(name:id:_:)` plus `SpanHandle` child helpers |"))
  #expect(source.contains("| `TraceHandle` in `.run { ... }` | `SpanHandle` in `.run { ... }` |"))
}
}
