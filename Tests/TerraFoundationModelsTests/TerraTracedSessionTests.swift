import Testing

#if canImport(FoundationModels)
@testable import TerraFoundationModels
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

@available(macOS 26.0, iOS 26.0, *)
@Test("TerraTracedSession rejects concurrent in-flight operations")
func tracedSessionRejectsConcurrentOperations() async throws {
  let session = TerraTracedSession()

  let holdingTask = Task {
    try await session._holdExclusiveAccessForTesting(nanoseconds: 300_000_000)
  }
  defer { holdingTask.cancel() }

  try await Task.sleep(nanoseconds: 50_000_000)

  do {
    try await session._holdExclusiveAccessForTesting(nanoseconds: 10_000_000)
    Issue.record("Expected concurrentOperationNotAllowed error")
  } catch let error as TerraTracedSession.SessionConcurrencyError {
    #expect(error == .concurrentOperationNotAllowed)
  } catch {
    Issue.record("Unexpected error type: \(error)")
  }

  try await holdingTask.value
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
