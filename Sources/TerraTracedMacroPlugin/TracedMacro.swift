import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
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
  static let runtimeParamNames: Set<String> = ["runtime", "runtimeID", "runtimeId"]

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
      provider: params.first { matches($0, names: ["provider"]) }.map(providerExpression),
      runtime: params.first { matches($0, names: runtimeParamNames) }.map(runtimeExpression),
      toolCallID: params.first { matches($0, names: toolCallIDParamNames) }.map(toolCallIDExpression),
      toolCallIDIsOptional: params.first { matches($0, names: toolCallIDParamNames) }.map { normalizedTypeName($0.type).isOptional } ?? false,
      embeddingInputCount: params.first { matches($0, names: embeddingCountParamNames) }.map(parameterName),
      safetySubject: params.first { matches($0, names: safetySubjectParamNames) }.map(parameterName)
    )
    let resolved = ResolvedArguments(
      arguments: arguments,
      detected: detected,
      diagnosticNode: node,
      context: context
    )
    let operation = try resolveOperation(arguments)
    let callExpression = try makeBaseCallExpression(
      operation: operation,
      arguments: arguments,
      resolved: resolved,
      diagnosticNode: node,
      context: context
    )

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
        return \(raw: tryKeyword)\(raw: awaitKeyword)\(raw: callExpression).run { trace in
          _ = trace
          \(raw: originalStatements)
        }
        """
    } else {
      wrappedCode = """
        \(raw: tryKeyword)\(raw: awaitKeyword)\(raw: callExpression).run { trace in
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
    resolved: ResolvedArguments,
    diagnosticNode: AttributeSyntax,
    context: some MacroExpansionContext
  ) throws -> String {
    switch operation {
    case .model:
      let modelExpr = try requiredArg(named: "model", in: arguments)
      let streamingArg = argument(named: "streaming", in: arguments)
      let forceStreaming = streamingArg == "true"
      let inference = buildModelCall(
        kind: "infer",
        modelExpr: modelExpr,
        promptExpr: resolved.prompt,
        providerExpr: resolved.provider,
        runtimeExpr: resolved.runtime,
        temperatureExpr: resolved.temperature,
        maxTokensExpr: resolved.maxOutputTokens
      )
      let stream = buildModelCall(
        kind: "stream",
        modelExpr: modelExpr,
        promptExpr: resolved.prompt,
        providerExpr: resolved.provider,
        runtimeExpr: resolved.runtime,
        temperatureExpr: resolved.temperature,
        maxTokensExpr: resolved.maxOutputTokens
      )
      if forceStreaming {
        return stream
      }
      return inference

    case .agent:
      let agentExpr = try requiredArg(named: "agent", in: arguments)
      let idExpr = argument(named: "id", in: arguments)
      return buildCall(
        "Terra.agent(\(agentExpr)",
        labeledArguments: [("id", idExpr), ("provider", resolved.provider), ("runtime", resolved.runtime)]
      )

    case .tool:
      let toolExpr = try requiredArg(named: "tool", in: arguments)
      let typeExpr = argument(named: "type", in: arguments)
      return buildToolCall(
        toolExpr: toolExpr,
        callIDExpr: resolved.toolCallID,
        callIDIsOptional: resolved.toolCallIDIsOptional,
        typeExpr: typeExpr,
        providerExpr: resolved.provider,
        runtimeExpr: resolved.runtime
      )

    case .embedding:
      let embeddingExpr = try requiredArg(named: "embedding", in: arguments)
      return buildCall(
        "Terra.embed(\(embeddingExpr)",
        labeledArguments: [("inputCount", resolved.embeddingInputCount), ("provider", resolved.provider), ("runtime", resolved.runtime)]
      )

    case .safety:
      let safetyExpr = try requiredArg(named: "safety", in: arguments)
      return buildCall(
        "Terra.safety(\(safetyExpr)",
        labeledArguments: [("subject", resolved.safetySubject), ("provider", resolved.provider), ("runtime", resolved.runtime)]
      )
    }
  }

  private static func buildModelCall(
    kind: String,
    modelExpr: String,
    promptExpr: String?,
    providerExpr: String?,
    runtimeExpr: String?,
    temperatureExpr: String?,
    maxTokensExpr: String?
  ) -> String {
    buildCall(
      "Terra.\(kind)(\(modelExpr)",
      labeledArguments: [
        ("prompt", promptExpr),
        ("provider", providerExpr),
        ("runtime", runtimeExpr),
        ("temperature", temperatureExpr),
        ("maxTokens", maxTokensExpr),
      ]
    )
  }

  private static func buildCall(
    _ prefix: String,
    labeledArguments: [(label: String, value: String?)]
  ) -> String {
    let rendered = labeledArguments.compactMap { pair -> String? in
      guard let value = pair.value else { return nil }
      return "\(pair.label): \(value)"
    }
    guard !rendered.isEmpty else { return "\(prefix))" }
    return "\(prefix), \(rendered.joined(separator: ", ")))"
  }

  private static func buildToolCall(
    toolExpr: String,
    callIDExpr: String?,
    callIDIsOptional: Bool,
    typeExpr: String?,
    providerExpr: String?,
    runtimeExpr: String?
  ) -> String {
    if let callIDExpr {
      if callIDIsOptional {
        let explicitCall = buildCall(
          "Terra.tool(\(toolExpr)",
          labeledArguments: [("callId", "$0"), ("type", typeExpr), ("provider", providerExpr), ("runtime", runtimeExpr)]
        )
        let fallbackCall = buildCall(
          "Terra.tool(\(toolExpr)",
          labeledArguments: [("type", typeExpr), ("provider", providerExpr), ("runtime", runtimeExpr)]
        )
        return "(\(callIDExpr).map { \(explicitCall) } ?? \(fallbackCall))"
      }

      return buildCall(
        "Terra.tool(\(toolExpr)",
        labeledArguments: [("callId", callIDExpr), ("type", typeExpr), ("provider", providerExpr), ("runtime", runtimeExpr)]
      )
    }

    return buildCall(
      "Terra.tool(\(toolExpr)",
      labeledArguments: [("type", typeExpr), ("provider", providerExpr), ("runtime", runtimeExpr)]
    )
  }

  private struct DetectedParameters {
    let modelPrompt: String?
    let maxOutputTokens: String?
    let temperature: String?
    let provider: String?
    let runtime: String?
    let toolCallID: String?
    let toolCallIDIsOptional: Bool
    let embeddingInputCount: String?
    let safetySubject: String?
  }

  private struct ResolvedArguments {
    let prompt: String?
    let maxOutputTokens: String?
    let temperature: String?
    let provider: String?
    let runtime: String?
    let toolCallID: String?
    let toolCallIDIsOptional: Bool
    let embeddingInputCount: String?
    let safetySubject: String?

    init(
      arguments: LabeledExprListSyntax,
      detected: DetectedParameters,
      diagnosticNode: AttributeSyntax,
      context: some MacroExpansionContext
    ) {
      // Priority: 1. Explicit macro args  2. Auto-detected function params  3. Omitted (nil)
      prompt = TracedMacro.argument(named: "prompt", in: arguments) ?? detected.modelPrompt

      maxOutputTokens =
        TracedMacro.argument(named: "maxOutputTokens", in: arguments)
        ?? TracedMacro.argument(named: "maxTokens", in: arguments)
        ?? detected.maxOutputTokens

      temperature = TracedMacro.argument(named: "temperature", in: arguments) ?? detected.temperature
      provider =
        TracedMacro.typedArgument(
          named: "provider",
          wrapperType: "Terra.ProviderID",
          diagnosticMessage: "@Traced provider expects Terra.ProviderID; wrap string literal with Terra.ProviderID(...)",
          fixItMessage: "wrap with Terra.ProviderID(...)",
          in: arguments,
          diagnosticNode: diagnosticNode,
          context: context
        )
        ?? detected.provider
      runtime =
        TracedMacro.typedArgument(
          named: "runtime",
          wrapperType: "Terra.RuntimeID",
          diagnosticMessage: "@Traced runtime expects Terra.RuntimeID; wrap string literal with Terra.RuntimeID(...)",
          fixItMessage: "wrap with Terra.RuntimeID(...)",
          in: arguments,
          diagnosticNode: diagnosticNode,
          context: context
        )
        ?? detected.runtime
      let explicitToolCallID =
        TracedMacro.argument(named: "callId", in: arguments)
        ?? TracedMacro.argument(named: "callID", in: arguments)
      toolCallID = explicitToolCallID ?? detected.toolCallID
      toolCallIDIsOptional = explicitToolCallID == nil ? detected.toolCallIDIsOptional : false

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

  private static func typedArgument(
    named label: String,
    wrapperType: String,
    diagnosticMessage: String,
    fixItMessage: String,
    in arguments: LabeledExprListSyntax,
    diagnosticNode: AttributeSyntax,
    context: some MacroExpansionContext
  ) -> String? {
    guard let argument = arguments.first(where: { $0.label?.text == label }) else {
      return nil
    }
    return wrappedTypedIDExpression(
      argument.expression,
      wrapperType: wrapperType,
      diagnosticMessage: diagnosticMessage,
      fixItMessage: fixItMessage,
      diagnosticNode: diagnosticNode,
      context: context
    )
  }

  private static func wrappedTypedIDExpression(
    _ expression: ExprSyntax,
    wrapperType: String,
    diagnosticMessage: String,
    fixItMessage: String,
    diagnosticNode: AttributeSyntax,
    context: some MacroExpansionContext
  ) -> String {
    let expressionText = expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard expression.is(StringLiteralExprSyntax.self) else {
      return expressionText
    }

    let wrappedExpression = "\(wrapperType)(\(expressionText))"
    let replacementExpr: ExprSyntax = "\(raw: wrappedExpression)"

    context.diagnose(
      Diagnostic(
        node: Syntax(diagnosticNode),
        message: TracedDiagnosticMessage(
          message: diagnosticMessage,
          diagnosticID: .init(domain: "TerraTracedMacro", id: "raw_string_\(wrapperType)"),
          severity: .warning
        ),
        fixIts: [
          FixIt(
            message: TracedFixItMessage(
              message: fixItMessage,
              fixItID: .init(domain: "TerraTracedMacro", id: "wrap_\(wrapperType)")
            ),
            changes: [.replace(oldNode: Syntax(expression), newNode: Syntax(replacementExpr))]
          )
        ]
      )
    )

    return wrappedExpression
  }

  private static func providerExpression(_ param: FunctionParameterSyntax) -> String {
    let name = parameterName(param)
    let type = normalizedTypeName(param.type)

    switch type {
    case ("String", false):
      return "Terra.ProviderID(\(name))"
    case ("String", true):
      return "\(name).map { Terra.ProviderID($0) }"
    case ("ProviderID", _), ("Terra.ProviderID", _):
      return name
    default:
      return name
    }
  }

  private static func toolCallIDExpression(_ param: FunctionParameterSyntax) -> String {
    let name = parameterName(param)
    let type = normalizedTypeName(param.type)

    switch type {
    case ("String", false):
      return name
    case ("String", true):
      return name
    case ("ToolCallID", false), ("Terra.ToolCallID", false):
      return name
    case ("ToolCallID", true), ("Terra.ToolCallID", true):
      return name
    default:
      return name
    }
  }

  private static func runtimeExpression(_ param: FunctionParameterSyntax) -> String {
    let name = parameterName(param)
    let type = normalizedTypeName(param.type)

    switch type {
    case ("String", false):
      return "Terra.RuntimeID(\(name))"
    case ("String", true):
      return "\(name).map { Terra.RuntimeID($0) }"
    case ("RuntimeID", _), ("Terra.RuntimeID", _):
      return name
    default:
      return name
    }
  }

  private static func normalizedTypeName(_ type: TypeSyntax?) -> (name: String, isOptional: Bool) {
    guard var type else { return ("", false) }

    var isOptional = false
    if let optionalType = type.as(OptionalTypeSyntax.self) {
      isOptional = true
      type = optionalType.wrappedType
    } else if let optionalType = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      isOptional = true
      type = optionalType.wrappedType
    }

    if let identifierType = type.as(IdentifierTypeSyntax.self) {
      return (identifierType.name.text, isOptional)
    }

    if let memberType = type.as(MemberTypeSyntax.self) {
      let base = memberType.baseType.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return ("\(base).\(memberType.name.text)", isOptional)
    }

    return (type.description.trimmingCharacters(in: .whitespacesAndNewlines), isOptional)
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

private struct TracedDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity
}

private struct TracedFixItMessage: FixItMessage {
  let message: String
  let fixItID: MessageID
}
