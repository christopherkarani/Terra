#if canImport(CoreML)
import CoreML
import OpenTelemetryApi
import Testing
@testable import TerraCoreML
@testable import TerraCore

// MARK: - Keys Constants

@Test("Keys.runtime has expected value")
func keysRuntimeValue() {
  #expect(TerraCoreML.Keys.runtime == "terra.runtime")
}

@Test("Keys.computeUnits has expected value")
func keysComputeUnitsValue() {
  #expect(TerraCoreML.Keys.computeUnits == "terra.coreml.compute_units")
}

// MARK: - Compute Unit Label Mapping

@Test("attributes maps MLComputeUnits.all to 'all'")
func computeUnitsAll() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("all"))
}

@Test("attributes maps MLComputeUnits.cpuOnly to 'cpu_only'")
func computeUnitsCPUOnly() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuOnly)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_only"))
}

@Test("attributes maps MLComputeUnits.cpuAndGPU to 'cpu_and_gpu'")
func computeUnitsCPUAndGPU() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuAndGPU)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_and_gpu"))
}

@Test("attributes maps MLComputeUnits.cpuAndNeuralEngine to 'cpu_and_ane'")
func computeUnitsCPUAndNeuralEngine() {
  let attrs = TerraCoreML.attributes(computeUnits: .cpuAndNeuralEngine)
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("cpu_and_ane"))
}

// MARK: - attributes(computeUnits:) Structure

@Test("attributes(computeUnits:) returns both runtime and compute_units keys")
func attributesContainsBothKeys() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[TerraCoreML.Keys.runtime] == .string("coreml"))
  #expect(attrs[TerraCoreML.Keys.computeUnits] == .string("all"))
  #expect(attrs.count == 2)
}

// MARK: - attributes(configuration:) Equivalence

@Test("attributes(configuration:) produces same result as attributes(computeUnits:)")
func configurationAttributesMatchComputeUnitsAttributes() {
  let config = MLModelConfiguration()
  config.computeUnits = .cpuAndGPU

  let fromConfig = TerraCoreML.attributes(configuration: config)
  let fromUnits = TerraCoreML.attributes(computeUnits: .cpuAndGPU)

  #expect(fromConfig == fromUnits)
}

// MARK: - Route Evidence API Contract

@Test("routeEvidence maps compute units into typed execution-route evidence")
func routeEvidenceMapsComputeUnits() {
  let evidence = TerraCoreML.routeEvidence(
    computeUnits: .cpuAndNeuralEngine,
    captureMode: .requestedOnly,
    confidence: .high
  )

  #expect(evidence.requested == "cpu_ane")
  #expect(evidence.captureMode == .requestedOnly)
  #expect(evidence.confidence == .high)
}

@Test("execution-route evidence renders OTel attributes with expected keys")
func executionRouteEvidenceAttributes() {
  let evidence = Terra.ExecutionRouteEvidence(
    requested: "cpu_gpu",
    observed: "gpu",
    estimatedPrimary: "gpu",
    supported: ["cpu", "gpu"],
    captureMode: .explicitObserved,
    confidence: .medium
  )

  let attributes = evidence.attributes
  #expect(attributes[Terra.Keys.Terra.execRouteRequested] == .string("cpu_gpu"))
  #expect(attributes[Terra.Keys.Terra.execRouteObserved] == .string("gpu"))
  #expect(attributes[Terra.Keys.Terra.execRouteEstimatedPrimary] == .string("gpu"))
  #expect(attributes[Terra.Keys.Terra.execRouteSupported] == .string("cpu,gpu"))
  #expect(attributes[Terra.Keys.Terra.execRouteCaptureMode] == .string("explicit_observed"))
  #expect(attributes[Terra.Keys.Terra.execRouteConfidence] == .string("medium"))
}

// MARK: - CoreMLInstrumentation Name Sanitization

@Test("sanitizeModelName strips control characters")
func sanitizeModelNameStripsControlCharacters() {
  let sanitized = CoreMLInstrumentation.sanitizeModelName("model\u{0000}\u{0007}-v1")
  #expect(sanitized == "model-v1")
}

@Test("sanitizeModelName trims and bounds name length to 256")
func sanitizeModelNameBoundsLength() {
  let longName = String(repeating: "a", count: 300)
  let sanitized = CoreMLInstrumentation.sanitizeModelName("  \(longName)  ")
  #expect(sanitized?.count == 256)
}

@Test("CoreML attributes never include prompt or response content keys")
func coreMLAttributesExcludeContent() {
  let attrs = TerraCoreML.attributes(computeUnits: .all)
  #expect(attrs[Terra.Keys.Terra.promptLength] == nil)
  #expect(attrs[Terra.Keys.Terra.promptHMACSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.promptSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectLength] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectHMACSHA256] == nil)
  #expect(attrs[Terra.Keys.Terra.safetySubjectSHA256] == nil)
}
#endif
