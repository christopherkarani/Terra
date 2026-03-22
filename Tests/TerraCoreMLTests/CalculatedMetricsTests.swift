import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraCoreML

@Suite("CalculatedMetrics")
struct CalculatedMetricsTests {

  @Test("1GB model + 1s = 1.0 GB/s bandwidth")
  func bandwidthCalculation() {
    let size = ModelSizeDetector.ModelSize(
      totalBytes: 1_000_000_000,  // 1 GB
      weightFileCount: 1,
      format: .compiledModel
    )
    let metrics = CalculatedMetrics(modelSize: size, inferenceTimeMs: 1000)
    #expect(metrics.bandwidthGBs == 1.0)
  }

  @Test("zero inference time returns zero bandwidth")
  func zeroBandwidth() {
    let size = ModelSizeDetector.ModelSize(
      totalBytes: 1_000_000_000,
      weightFileCount: 1,
      format: .compiledModel
    )
    let metrics = CalculatedMetrics(modelSize: size, inferenceTimeMs: 0)
    #expect(metrics.bandwidthGBs == 0)
  }

  @Test("telemetry attributes include model size and bandwidth")
  func telemetryAttributes() {
    let size = ModelSizeDetector.ModelSize(
      totalBytes: 500_000_000,
      weightFileCount: 2,
      format: .compiledModel
    )
    let metrics = CalculatedMetrics(modelSize: size, inferenceTimeMs: 500)
    let attrs = metrics.telemetryAttributes

    #expect(attrs["terra.model.size_bytes"] == AttributeValue.int(500_000_000))
    #expect(attrs["terra.model.bandwidth_gbps"] == AttributeValue.double(1.0))
    #expect(attrs["terra.model.inference_time_ms"] == AttributeValue.double(500.0))
  }
}

@Suite("ComputeDeviceGuess")
struct ComputeDeviceGuessTests {

  @Test("< 20ms → likely ANE")
  func likelyANE() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 19)
    #expect(guess == .likelyANE)
  }

  @Test("20ms boundary → likely GPU")
  func boundary20ms() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 20)
    #expect(guess == .likelyGPU)
  }

  @Test("99ms → likely GPU")
  func likelyGPU() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 99)
    #expect(guess == .likelyGPU)
  }

  @Test("100ms boundary → likely CPU")
  func boundary100ms() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 100)
    #expect(guess == .likelyCPU)
  }

  @Test("telemetry attributes")
  func telemetryAttributes() {
    let guess = ComputeDeviceGuess.likelyANE
    let attrs = guess.telemetryAttributes
    #expect(attrs["terra.model.compute_device_guess"] == AttributeValue.string("likely_ane"))
  }

  #if canImport(CoreML)
  @Test("cpuOnly → always CPU regardless of speed")
  func cpuOnlyNarrowing() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 5, computeUnits: .cpuOnly)
    #expect(guess == .likelyCPU)
  }

  @Test("cpuAndNeuralEngine fast → likely ANE")
  func cpuAndANEFast() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 10, computeUnits: .cpuAndNeuralEngine)
    #expect(guess == .likelyANE)
  }

  @Test("cpuAndNeuralEngine slow → likely CPU")
  func cpuAndANESlow() {
    let guess = ComputeDeviceGuess(inferenceTimeMs: 150, computeUnits: .cpuAndNeuralEngine)
    #expect(guess == .likelyCPU)
  }
  #endif
}
