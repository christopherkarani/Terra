#if canImport(FoundationModels)
import TerraCore

@available(macOS 26.0, iOS 26.0, *)
extension Terra {
  /// Convenience alias for `TerraTracedSession`.
  public typealias TracedSession = TerraTracedSession
}
#endif
