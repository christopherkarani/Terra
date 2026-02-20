import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct TerraTracedMacroPluginEntry: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    TracedMacro.self,
  ]
}

public struct TracedMacro: BodyMacro {
  // Known parameter names for auto-detection
  static let promptParamNames: Set<String> = ["prompt", "input", "query", "text"]
  static let maxTokensParamNames: Set<String> = ["maxTokens", "maxOutputTokens", "max_tokens"]

  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    // 1. Extract model string from @Traced(model: "...")
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
          let modelArg = arguments.first(where: { $0.label?.text == "model" }),
          let modelLiteral = modelArg.expression.as(StringLiteralExprSyntax.self),
          let modelValue = modelLiteral.segments.first?.as(StringSegmentSyntax.self)?.content.text
    else {
      throw MacroError.missingModelArgument
    }

    // 2. Get the function declaration to scan parameters
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroError.notAFunction
    }

    // 3. Get original body
    guard let body = funcDecl.body else {
      throw MacroError.missingBody
    }

    // 4. Scan parameters
    let params = funcDecl.signature.parameterClause.parameters
    func matches(_ param: FunctionParameterSyntax, names: Set<String>) -> Bool {
      let first = param.firstName.text
      let second = param.secondName?.text
      return names.contains(first) || (second.map(names.contains) ?? false)
    }

    let promptParam = params.first { matches($0, names: promptParamNames) }
    let maxTokensParam = params.first { matches($0, names: maxTokensParamNames) }

    // 5. Build InferenceRequest arguments
    var requestArgs = "model: \"\(modelValue)\""
    if let promptParam {
      let paramName = promptParam.secondName?.text ?? promptParam.firstName.text
      requestArgs += ", prompt: \(paramName)"
    }
    if let maxTokensParam {
      let paramName = maxTokensParam.secondName?.text ?? maxTokensParam.firstName.text
      requestArgs += ", maxOutputTokens: \(paramName)"
    }

    // 6. Check if function is async/throws
    let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
    let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil
    let returnTypeText = funcDecl.signature.returnClause?.type.description
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasNonVoidReturn = {
      guard let returnTypeText else { return false }
      return returnTypeText != "Void" && returnTypeText != "()"
    }()

    guard isAsync else {
      throw MacroError.requiresAsyncFunction
    }

    let tryKeyword = isThrows ? "try " : ""
    let awaitKeyword = isAsync ? "await " : ""

    // 7. Build the wrapped body
    let originalStatements = body.statements.map { "\($0)" }.joined(separator: "\n")

    let wrappedCode: CodeBlockItemSyntax
    if hasNonVoidReturn {
      wrappedCode = """
        return \(raw: tryKeyword)\(raw: awaitKeyword)Terra.withInferenceSpan(
          .init(\(raw: requestArgs))
        ) { scope in
          \(raw: originalStatements)
        }
        """
    } else {
      wrappedCode = """
        \(raw: tryKeyword)\(raw: awaitKeyword)Terra.withInferenceSpan(
          .init(\(raw: requestArgs))
        ) { scope in
          \(raw: originalStatements)
        }
        """
    }

    return [wrappedCode]
  }

  enum MacroError: Error, CustomStringConvertible {
    case missingModelArgument
    case notAFunction
    case missingBody
    case requiresAsyncFunction

    var description: String {
      switch self {
      case .missingModelArgument:
        return "@Traced requires a 'model' argument, e.g. @Traced(model: \"my-model\")"
      case .notAFunction:
        return "@Traced can only be applied to functions"
      case .missingBody:
        return "@Traced requires a function with a body"
      case .requiresAsyncFunction:
        return "@Traced currently supports async functions only because it wraps Terra.withInferenceSpan"
      }
    }
  }
}
