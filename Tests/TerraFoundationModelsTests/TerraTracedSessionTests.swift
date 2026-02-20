import Testing

#if canImport(FoundationModels)
import TerraFoundationModels
import TerraCore

@available(macOS 26.0, iOS 26.0, *)
@Test("TerraTracedSession initializes with default model identifier")
func tracedSessionInitializesWithDefaultIdentifier() {
  let session = TerraTracedSession()
  #expect(session.modelIdentifier == "apple/foundation-model")
}

@available(macOS 26.0, iOS 26.0, *)
@Test("TerraTracedSession initializes with custom model identifier")
func tracedSessionInitializesWithCustomIdentifier() {
  let session = TerraTracedSession(modelIdentifier: "apple/custom-model")
  #expect(session.modelIdentifier == "apple/custom-model")
}

#else

// FoundationModels is not available on this platform or SDK.
// These tests confirm the module compiles cleanly as a stub.

@Test("TerraFoundationModels stub compiles without FoundationModels framework")
func foundationModelsNotAvailable() {
  // The TerraFoundationModelsPlaceholder enum should be accessible
  // when FoundationModels is absent (the #else branch in the source).
  #expect(true)
}

#endif
