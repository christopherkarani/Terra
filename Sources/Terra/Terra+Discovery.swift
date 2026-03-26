import Foundation

extension Terra {
  /// Structured metadata describing a Terra capability.
  ///
  /// Use capabilities to discover the SDK surface without reading implementation files.
  public struct Capability: Sendable, Hashable {
    public enum Preference: String, Sendable, Hashable {
      case primary
      case secondary
      case compatibility
    }

    public let name: String
    public let description: String
    public let example: String
    public let entryPoint: String
    public let preference: Preference

    public init(
      name: String,
      description: String,
      example: String,
      entryPoint: String,
      preference: Preference = .primary
    ) {
      self.name = name
      self.description = description
      self.example = example
      self.entryPoint = entryPoint
      self.preference = preference
    }
  }

  /// A copy-paste guide for a common Terra workflow.
  public struct Guide: Sendable, Hashable {
    public let title: String
    public let problem: String
    public let solution: String
    public let codeExample: String

    public init(title: String, problem: String, solution: String, codeExample: String) {
      self.title = title
      self.problem = problem
      self.solution = solution
      self.codeExample = codeExample
    }
  }

  /// A runnable Terra example that coding agents can inspect and adapt directly.
  public struct Example: Sendable, Hashable {
    public let title: String
    public let scenario: String
    public let code: String
    public let complexity: ExampleComplexity

    public init(title: String, scenario: String, code: String, complexity: ExampleComplexity) {
      self.title = title
      self.scenario = scenario
      self.code = code
      self.complexity = complexity
    }
  }

  /// Complexity level for built-in Terra examples.
  public enum ExampleComplexity: String, Sendable, Hashable {
    case beginner
    case intermediate
    case advanced
  }

  /// Deterministic guidance returned from `Terra.ask(_:)`.
  public struct Guidance: Sendable, Hashable {
    public let why: String
    public let apiToUse: String
    public let codeExample: String
    public let commonMistakes: [String]

    public init(
      why: String,
      apiToUse: String,
      codeExample: String,
      commonMistakes: [String]
    ) {
      self.why = why
      self.apiToUse = apiToUse
      self.codeExample = codeExample
      self.commonMistakes = commonMistakes
    }
  }

  /// Returns Terra's discoverable capabilities for coding agents and humans.
  public static func capabilities() -> [Capability] {
    _capabilityCatalog
  }

  /// Returns a printable help tree covering Terra's start-here path, primary tracing APIs, and compatibility notes.
  public static func help() -> String {
    _helpTree()
  }

  /// Returns opinionated guides for common Terra workflows.
  public static func guides() -> [Guide] {
    _guideCatalog
  }

  /// Returns runnable Terra examples that agents can copy and adapt directly.
  public static func examples() -> [Example] {
    _exampleCatalog
  }

  /// Ask Terra how to implement a workflow in plain English.
  ///
  /// `ask(_:)` is deterministic and offline. It does not call a model.
  public static func ask(_ question: String) -> Guidance {
    _guidance(for: question)
  }
}
