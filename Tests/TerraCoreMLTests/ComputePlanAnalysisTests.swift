import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraCoreML

#if canImport(CoreML)
@Suite("ComputePlanAnalysis")
struct ComputePlanAnalysisTests {

  private func makeSummary(
    ops: [TerraCoreMLComputePlanOperationEstimate]
  ) -> TerraCoreMLComputePlanSummary {
    TerraCoreMLComputePlanSummary(
      captureStatus: .captured,
      modelStructure: "program",
      estimatedPrimaryDevice: "mixed",
      supportedDevices: ["ane", "gpu", "cpu"],
      nodeCount: ops.count,
      captureDurationMS: 1.0,
      operationEstimates: ops,
      errorType: nil
    )
  }

  private func makeOp(device: String) -> TerraCoreMLComputePlanOperationEstimate {
    TerraCoreMLComputePlanOperationEstimate(
      identifier: "op.\(UUID().uuidString.prefix(4))",
      kind: "program_operation",
      preferredDevice: device,
      supportedDevices: [device]
    )
  }

  @Test("counts ops by device correctly")
  func opCounting() {
    let summary = makeSummary(ops: [
      makeOp(device: "ane"),
      makeOp(device: "ane"),
      makeOp(device: "gpu"),
      makeOp(device: "cpu"),
    ])
    let analysis = ComputePlanAnalysis.analyze(summary)
    #expect(analysis.totalOps == 4)
    #expect(analysis.aneOps == 2)
    #expect(analysis.gpuOps == 1)
    #expect(analysis.cpuOps == 1)
  }

  @Test("aneUtilization fraction")
  func aneUtilization() {
    let summary = makeSummary(ops: [
      makeOp(device: "ane"),
      makeOp(device: "ane"),
      makeOp(device: "ane"),
      makeOp(device: "gpu"),
    ])
    let analysis = ComputePlanAnalysis.analyze(summary)
    #expect(analysis.aneUtilization == 0.75)
  }

  @Test("aneUtilization zero for empty ops")
  func aneUtilizationEmpty() {
    let summary = makeSummary(ops: [])
    let analysis = ComputePlanAnalysis.analyze(summary)
    #expect(analysis.aneUtilization == 0)
  }

  @Test("dominant device detection")
  func dominantDevice() {
    let aneHeavy = makeSummary(ops: [
      makeOp(device: "ane"), makeOp(device: "ane"), makeOp(device: "gpu"),
    ])
    #expect(ComputePlanAnalysis.analyze(aneHeavy).dominantDevice == "ane")

    let gpuHeavy = makeSummary(ops: [
      makeOp(device: "gpu"), makeOp(device: "gpu"), makeOp(device: "ane"),
    ])
    #expect(ComputePlanAnalysis.analyze(gpuHeavy).dominantDevice == "gpu")

    let cpuHeavy = makeSummary(ops: [
      makeOp(device: "cpu"), makeOp(device: "cpu"), makeOp(device: "ane"),
    ])
    #expect(ComputePlanAnalysis.analyze(cpuHeavy).dominantDevice == "cpu")
  }

  @Test("mixed execution detection")
  func mixedExecution() {
    let mixed = makeSummary(ops: [makeOp(device: "ane"), makeOp(device: "gpu")])
    #expect(ComputePlanAnalysis.analyze(mixed).isMixedExecution)

    let singleDevice = makeSummary(ops: [makeOp(device: "ane"), makeOp(device: "ane")])
    #expect(!ComputePlanAnalysis.analyze(singleDevice).isMixedExecution)
  }

  @Test("ANE fallback assessment: high ANE ratio + slow → likely")
  func aneFallbackLikely() {
    let summary = makeSummary(ops: (0..<9).map { _ in makeOp(device: "ane") } + [makeOp(device: "gpu")])
    let analysis = ComputePlanAnalysis.analyze(summary)
    let assessment = analysis.assessANEFallback(observedInferenceTimeMs: 200)
    #expect(assessment.isFallbackLikely)
    #expect(assessment.confidence == .high)
  }

  @Test("ANE fallback assessment: high ANE ratio + fast → not likely")
  func aneFallbackNotLikely() {
    let summary = makeSummary(ops: (0..<9).map { _ in makeOp(device: "ane") } + [makeOp(device: "gpu")])
    let analysis = ComputePlanAnalysis.analyze(summary)
    let assessment = analysis.assessANEFallback(observedInferenceTimeMs: 10)
    #expect(!assessment.isFallbackLikely)
  }

  @Test("telemetry attributes output")
  func telemetryAttributes() {
    let summary = makeSummary(ops: [
      makeOp(device: "ane"), makeOp(device: "gpu"), makeOp(device: "cpu"),
    ])
    let analysis = ComputePlanAnalysis.analyze(summary)
    let attrs = analysis.telemetryAttributes
    #expect(attrs["terra.compute_plan.total_ops"] == AttributeValue.int(3))
    #expect(attrs["terra.compute_plan.is_mixed_execution"] == AttributeValue.bool(true))
  }

  @Test("ANEFallbackAssessment telemetry attributes")
  func fallbackAttributes() {
    let assessment = ANEFallbackAssessment(isFallbackLikely: true, confidence: .high)
    let attrs = assessment.telemetryAttributes
    #expect(attrs["terra.ane.fallback_likely"] == AttributeValue.bool(true))
    #expect(attrs["terra.ane.fallback_confidence"] == AttributeValue.string("high"))
  }
}
#endif
