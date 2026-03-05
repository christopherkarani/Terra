extension Terra {
  package protocol TerraTraceable {
    var terraTokenUsage: TokenUsage? { get }
    var terraResponseModel: String? { get }
  }

  package struct TokenUsage: Sendable {
    package var input: Int?
    package var output: Int?

    package init(input: Int? = nil, output: Int? = nil) {
      self.input = input
      self.output = output
    }
  }
}
