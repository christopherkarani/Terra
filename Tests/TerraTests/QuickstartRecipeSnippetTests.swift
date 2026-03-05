import Foundation
import Testing

@Test("Quickstart snippets exist and use canonical composable APIs")
func quickstartSnippetsExistAndUseCanonicalAPIs() throws {
  let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let snippetsURL = repoRoot.appendingPathComponent("Examples/Terra Sample/RecipeSnippets.swift")
  let source = try String(contentsOf: snippetsURL)

  #expect(source.contains("static func ninetySecondPath"))
  #expect(source.contains("static func inferRecipe"))
  #expect(source.contains("static func toolRecipe"))
  #expect(source.contains("static func agentRecipe"))

  #expect(source.contains(".infer("))
  #expect(source.contains(".tool("))
  #expect(source.contains(".agent("))
}
