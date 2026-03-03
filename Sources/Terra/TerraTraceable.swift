extension Terra {
  public protocol TerraTraceable {
    var terraTokenUsage: TokenUsage? { get }
    var terraResponseModel: String? { get }
  }

  public struct TokenUsage: Sendable {
    public var input: Int?
    public var output: Int?

    public init(input: Int? = nil, output: Int? = nil) {
      self.input = input
      self.output = output
    }
  }
}
