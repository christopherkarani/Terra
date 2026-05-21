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
    "website/src/app/page.tsx",
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

// P1-15: every canonical cookbook recipe must have a compile-checked mirror.
//
// This test asserts that for every Swift fenced code block published in
// `README.md` and `Docs/cookbook.md`, `CookbookSnippetsCompileTests.swift`
// has a `// SNIPPET: <doc>#<n>` annotation. The mirror functions in that file
// fail the build if the cookbook recipe references removed types, wrong
// argument labels, or changed return types — catching stale docs at build
// time rather than at runtime in a downstream integrator.
@Test("Every published cookbook swift snippet has a compile-checked mirror")
func everyPublishedCookbookSwiftSnippetHasACompileCheckedMirror() throws {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let mirrorURL = repoRoot.appendingPathComponent(
    "Tests/TerraTests/CookbookSnippetsCompileTests.swift"
  )
  let mirrorSource = try String(contentsOf: mirrorURL)

  let mirrorAnnotations = Self.extractMirrorAnnotations(from: mirrorSource)

  let docsToCover: [String] = [
    "README.md",
    "Docs/cookbook.md",
  ]

  for relativePath in docsToCover {
    let doc = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    let docURL = repoRoot.appendingPathComponent(relativePath)
    let docSource = try String(contentsOf: docURL)
    let snippetCount = Self.countSwiftFences(in: docSource)
    let mirroredCount = mirrorAnnotations.filter { $0.hasPrefix("\(doc)#") }.count

    #expect(
      mirroredCount >= snippetCount,
      "\(relativePath) publishes \(snippetCount) swift snippet(s) but the mirror only annotates \(mirroredCount). Add one `// SNIPPET: \(doc)#<id>` block per recipe to CookbookSnippetsCompileTests.swift."
    )
  }
}

private static func extractMirrorAnnotations(from source: String) -> [String] {
  var annotations: [String] = []
  let prefix = "// SNIPPET: "
  for line in source.split(separator: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix(prefix) {
      annotations.append(String(trimmed.dropFirst(prefix.count)))
    }
  }
  return annotations
}

private static func countSwiftFences(in source: String) -> Int {
  // Count fenced code blocks opened with a `swift` language tag. The
  // pattern matches the start fence "```swift" at the beginning of a line.
  var count = 0
  var inFence = false
  for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("```") {
      if inFence {
        inFence = false
      } else {
        inFence = true
        if trimmed.lowercased() == "```swift" {
          count += 1
        }
      }
    }
  }
  return count
}
}
