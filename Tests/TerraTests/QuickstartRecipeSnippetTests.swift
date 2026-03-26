import Foundation
import Testing

@Suite("Quickstart snippets", .serialized)
struct QuickstartRecipeSnippetTests {
@Test("Quickstart snippets exist and use canonical workflow-first APIs")
func quickstartSnippetsExistAndUseCanonicalWorkflowFirstApis() throws {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let snippetsURL = repoRoot.appendingPathComponent("Examples/Terra Sample/RecipeSnippets.swift")
  let source = try String(contentsOf: snippetsURL)

  #expect(source.contains("static func ninetySecondPath"))
  #expect(source.contains("static func inferRecipe"))
  #expect(source.contains("static func toolRecipe"))
  #expect(source.contains("static func workflowRecipe"))

  #expect(source.contains(".infer("))
  #expect(source.contains(".tool("))
  #expect(source.contains(".workflow("))
  #expect(!source.contains("Terra.trace("))
  #expect(!source.contains("Terra.agentic("))
  #expect(!source.contains("Terra.loop("))
  #expect(!source.contains("Terra.ModelID("))
  #expect(!source.contains("Terra.ToolCallID("))
}
}
