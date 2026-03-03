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
  static let modelPromptParamNames: Set<String> = ["prompt", "input", "query", "text", "message"]
  static let safetySubjectParamNames: Set<String> = ["subject", "prompt", "input", "query", "text", "message"]
  static let maxTokensParamNames: Set<String> = ["maxTokens", "maxOutputTokens", "max_tokens"]
  static let toolCallIDParamNames: Set<String> = ["callID", "callId", "toolCallID", "toolCallId"]
  static let embeddingCountParamNames: Set<String> = ["count", "inputCount"]

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
    let detected = DetectedParameters(
      modelPrompt: params.first { matches($0, names: modelPromptParamNames) }.map(parameterName),
      maxOutputTokens: params.first { matches($0, names: maxTokensParamNames) }.map(parameterName),
      temperature: params.first { matches($0, names: ["temperature"]) }.map(parameterName),
      provider: params.first { matches($0, names: ["provider"]) }.map(parameterName),
      toolCallID: params.first { matches($0, names: toolCallIDParamNames) }.map(parameterName),
      embeddingInputCount: params.first { matches($0, names: embeddingCountParamNames) }.map(parameterName),
      safetySubject: params.first { matches($0, names: safetySubjectParamNames) }.map(parameterName)
    )
    let resolved = ResolvedArguments(arguments: arguments, detected: detected)
    let operation = try resolveOperation(arguments)
    var callExpression = try makeBaseCallExpression(
      operation: operation,
      arguments: arguments,
      resolved: resolved
    )

    if let maxOutputTokens = resolved.maxOutputTokens, operation == .model {
      callExpression += ".maxOutputTokens(\(maxOutputTokens))"
    }
    if let temperature = resolved.temperature, operation == .model {
      callExpression += ".temperature(\(temperature))"
    }
    if let provider = resolved.provider {
      callExpression += ".provider(\(provider))"
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
    resolved: ResolvedArguments
  ) throws -> String {
    switch operation {
    case .model:
      let modelExpr = try requiredArg(named: "model", in: arguments)
      let streamingArg = argument(named: "streaming", in: arguments)
      let forceStreaming = streamingArg == "true"
      let inference = buildModelCall(kind: "inference", modelExpr: modelExpr, promptExpr: resolved.prompt)
      let stream = buildModelCall(kind: "stream", modelExpr: modelExpr, promptExpr: resolved.prompt)
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
      let callIDExpr = resolved.toolCallID ?? "UUID().uuidString"
      let typeExpr = argument(named: "type", in: arguments)
      if let typeExpr {
        return "Terra.tool(name: \(toolExpr), callID: \(callIDExpr), type: \(typeExpr))"
      }
      return "Terra.tool(name: \(toolExpr), callID: \(callIDExpr))"

    case .embedding:
      let embeddingExpr = try requiredArg(named: "embedding", in: arguments)
      if let inputCount = resolved.embeddingInputCount {
        return "Terra.embedding(model: \(embeddingExpr), inputCount: \(inputCount))"
      }
      return "Terra.embedding(model: \(embeddingExpr))"

    case .safety:
      let safetyExpr = try requiredArg(named: "safety", in: arguments)
      if let subject = resolved.safetySubject {
        return "Terra.safetyCheck(name: \(safetyExpr), subject: \(subject))"
      }
      return "Terra.safetyCheck(name: \(safetyExpr))"
    }
  }

  private static func buildModelCall(kind: String, modelExpr: String, promptExpr: String?) -> String {
    var call = "Terra.\(kind)(model: \(modelExpr)"
    if let promptExpr {
      call += ", prompt: \(promptExpr)"
    }
    call += ")"
    return call
  }

  private struct DetectedParameters {
    let modelPrompt: String?
    let maxOutputTokens: String?
    let temperature: String?
    let provider: String?
    let toolCallID: String?
    let embeddingInputCount: String?
    let safetySubject: String?
  }

  private struct ResolvedArguments {
    let prompt: String?
    let maxOutputTokens: String?
    let temperature: String?
    let provider: String?
    let toolCallID: String?
    let embeddingInputCount: String?
    let safetySubject: String?

    init(arguments: LabeledExprListSyntax, detected: DetectedParameters) {
      // Priority: 1. Explicit macro args  2. Auto-detected function params  3. Omitted (nil)
      prompt = TracedMacro.argument(named: "prompt", in: arguments) ?? detected.modelPrompt

      maxOutputTokens =
        TracedMacro.argument(named: "maxOutputTokens", in: arguments)
        ?? TracedMacro.argument(named: "maxTokens", in: arguments)
        ?? detected.maxOutputTokens

      temperature = TracedMacro.argument(named: "temperature", in: arguments) ?? detected.temperature
      provider = TracedMacro.argument(named: "provider", in: arguments) ?? detected.provider
      toolCallID = TracedMacro.argument(named: "callID", in: arguments) ?? detected.toolCallID

      embeddingInputCount =
        TracedMacro.argument(named: "inputCount", in: arguments)
        ?? TracedMacro.argument(named: "count", in: arguments)
        ?? detected.embeddingInputCount

      safetySubject = TracedMacro.argument(named: "subject", in: arguments) ?? detected.safetySubject
    }
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
