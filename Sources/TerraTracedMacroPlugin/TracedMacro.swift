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
  static let promptParamNames: Set<String> = ["prompt", "input", "query", "text", "message", "subject"]
  static let maxTokensParamNames: Set<String> = ["maxTokens", "maxOutputTokens", "max_tokens"]

  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
      throw MacroError.missingOperationArgument
    }
    guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw MacroError.notAFunction
    }
    guard let body = funcDecl.body else {
      throw MacroError.missingBody
    }

    let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
    guard isAsync else {
      throw MacroError.requiresAsyncFunction
    }
    let isThrows = funcDecl.signature.effectSpecifiers?.throwsClause != nil

    let params = funcDecl.signature.parameterClause.parameters
    let promptParam = params.first { matches($0, names: promptParamNames) }.map(parameterName)
    let maxTokensParam = params.first { matches($0, names: maxTokensParamNames) }.map(parameterName)
    let temperatureParam = params.first { matches($0, names: ["temperature"]) }.map(parameterName)
    let providerParam = params.first { matches($0, names: ["provider"]) }.map(parameterName)
    let operation = try resolveOperation(arguments)
    var callExpression = try makeBaseCallExpression(
      operation: operation,
      arguments: arguments,
      promptParam: promptParam
    )

    if let maxTokensParam, operation == .model {
      callExpression += ".maxOutputTokens(\(maxTokensParam))"
    }
    if let temperatureParam, operation == .model {
      callExpression += ".temperature(\(temperatureParam))"
    }
    if let providerParam {
      callExpression += ".provider(\(providerParam))"
    }

    let returnTypeText = funcDecl.signature.returnClause?.type.description
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasNonVoidReturn = {
      guard let returnTypeText else { return false }
      return returnTypeText != "Void" && returnTypeText != "()"
    }()

    let tryKeyword = isThrows ? "try " : ""
    let awaitKeyword = "await "
    let originalStatements = body.statements.map { "\($0)" }.joined(separator: "\n")

    let wrappedCode: CodeBlockItemSyntax
    if hasNonVoidReturn {
      wrappedCode = """
        return \(raw: tryKeyword)\(raw: awaitKeyword)\(raw: callExpression).execute { trace in
          _ = trace
          \(raw: originalStatements)
        }
        """
    } else {
      wrappedCode = """
        \(raw: tryKeyword)\(raw: awaitKeyword)\(raw: callExpression).execute { trace in
          _ = trace
          \(raw: originalStatements)
        }
        """
    }

    return [wrappedCode]
  }

  private enum Operation {
    case model
    case agent
    case tool
    case embedding
    case safety
  }

  private static func resolveOperation(_ arguments: LabeledExprListSyntax) throws -> Operation {
    if arguments.first(where: { $0.label?.text == "model" }) != nil {
      return .model
    }
    if arguments.first(where: { $0.label?.text == "agent" }) != nil {
      return .agent
    }
    if arguments.first(where: { $0.label?.text == "tool" }) != nil {
      return .tool
    }
    if arguments.first(where: { $0.label?.text == "embedding" }) != nil {
      return .embedding
    }
    if arguments.first(where: { $0.label?.text == "safety" }) != nil {
      return .safety
    }
    throw MacroError.missingOperationArgument
  }

  private static func makeBaseCallExpression(
    operation: Operation,
    arguments: LabeledExprListSyntax,
    promptParam: String?
  ) throws -> String {
    switch operation {
    case .model:
      let modelExpr = try requiredArg(named: "model", in: arguments)
      let streamingArg = argument(named: "streaming", in: arguments)
      let forceStreaming = streamingArg == "true"
      let inference = buildModelCall(kind: "inference", modelExpr: modelExpr, promptParam: promptParam)
      let stream = buildModelCall(kind: "stream", modelExpr: modelExpr, promptParam: promptParam)
      if forceStreaming {
        return stream
      }
      return inference

    case .agent:
      let agentExpr = try requiredArg(named: "agent", in: arguments)
      let idExpr = argument(named: "id", in: arguments)
      if let idExpr {
        return "Terra.agent(name: \(agentExpr), id: \(idExpr))"
      }
      return "Terra.agent(name: \(agentExpr))"

    case .tool:
      let toolExpr = try requiredArg(named: "tool", in: arguments)
      let typeExpr = argument(named: "type", in: arguments)
      if let typeExpr {
        return "Terra.tool(name: \(toolExpr), callID: String(UInt64.random(in: 0...UInt64.max), radix: 16), type: \(typeExpr))"
      }
      return "Terra.tool(name: \(toolExpr), callID: String(UInt64.random(in: 0...UInt64.max), radix: 16))"

    case .embedding:
      let embeddingExpr = try requiredArg(named: "embedding", in: arguments)
      return "Terra.embedding(model: \(embeddingExpr))"

    case .safety:
      let safetyExpr = try requiredArg(named: "safety", in: arguments)
      if let promptParam {
        return "Terra.safetyCheck(name: \(safetyExpr), subject: \(promptParam))"
      }
      return "Terra.safetyCheck(name: \(safetyExpr))"
    }
  }

  private static func buildModelCall(kind: String, modelExpr: String, promptParam: String?) -> String {
    var call = "Terra.\(kind)(model: \(modelExpr)"
    if let promptParam {
      call += ", prompt: \(promptParam)"
    }
    call += ")"
    return call
  }

  private static func matches(_ param: FunctionParameterSyntax, names: Set<String>) -> Bool {
    let first = param.firstName.text
    let second = param.secondName?.text
    return names.contains(first) || (second.map(names.contains) ?? false)
  }

  private static func parameterName(_ param: FunctionParameterSyntax) -> String {
    if let second = param.secondName?.text {
      return second
    }
    return param.firstName.text
  }

  private static func argument(named label: String, in arguments: LabeledExprListSyntax) -> String? {
    arguments.first(where: { $0.label?.text == label })?.expression.description
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func requiredArg(named label: String, in arguments: LabeledExprListSyntax) throws -> String {
    guard let value = argument(named: label, in: arguments), !value.isEmpty else {
      throw MacroError.missingOperationArgument
    }
    return value
  }

  enum MacroError: Error, CustomStringConvertible {
    case missingOperationArgument
    case notAFunction
    case missingBody
    case requiresAsyncFunction

    var description: String {
      switch self {
      case .missingOperationArgument:
        return "@Traced requires one of: model:, agent:, tool:, embedding:, or safety:"
      case .notAFunction:
        return "@Traced can only be applied to functions"
      case .missingBody:
        return "@Traced requires a function with a body"
      case .requiresAsyncFunction:
        return "@Traced currently supports async functions only because it wraps Terra traced async APIs"
      }
    }
  }
}
