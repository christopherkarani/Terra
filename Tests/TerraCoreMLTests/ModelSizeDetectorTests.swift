import Foundation
import Testing
import OpenTelemetryApi
@testable import TerraCoreML

@Suite("ModelSizeDetector")
struct ModelSizeDetectorTests {

  @Test("detects size from .mlmodelc weights directory")
  func detectsMlmodelcSize() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-model-\(UUID().uuidString).mlmodelc")
    let weightsDir = tempDir.appendingPathComponent("weights")
    try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Write fake weight files
    let data1 = Data(repeating: 0xAB, count: 1024)
    let data2 = Data(repeating: 0xCD, count: 2048)
    try data1.write(to: weightsDir.appendingPathComponent("weights.bin"))
    try data2.write(to: weightsDir.appendingPathComponent("weights2.bin"))

    let result = ModelSizeDetector.detectSize(of: tempDir)
    #expect(result != nil)
    #expect(result?.totalBytes == 3072)
    #expect(result?.weightFileCount == 2)
    #expect(result?.format == .compiledModel)
  }

  @Test("detects size from .mlpackage weights directory")
  func detectsMlpackageSize() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-model-\(UUID().uuidString).mlpackage")
    let weightsDir = tempDir
      .appendingPathComponent("Data")
      .appendingPathComponent("com.apple.CoreML")
      .appendingPathComponent("weights")
    try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let data = Data(repeating: 0xFF, count: 4096)
    try data.write(to: weightsDir.appendingPathComponent("weight.espresso.weights"))

    let result = ModelSizeDetector.detectSize(of: tempDir)
    #expect(result != nil)
    #expect(result?.totalBytes == 4096)
    #expect(result?.weightFileCount == 1)
    #expect(result?.format == .modelPackage)
  }

  @Test("returns nil for non-existent path")
  func nilForNonExistent() {
    let url = URL(fileURLWithPath: "/nonexistent/model.mlmodelc")
    #expect(ModelSizeDetector.detectSize(of: url) == nil)
  }

  @Test("returns nil for unsupported format")
  func nilForUnsupported() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-model-\(UUID().uuidString).onnx")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    #expect(ModelSizeDetector.detectSize(of: tempDir) == nil)
  }

  @Test("ModelSize telemetry attributes")
  func modelSizeAttributes() {
    let size = ModelSizeDetector.ModelSize(
      totalBytes: 1_073_741_824,  // 1 GB
      weightFileCount: 3,
      format: .compiledModel
    )
    let attrs = size.telemetryAttributes
    #expect(attrs["terra.model.size_bytes"] == AttributeValue.int(1_073_741_824))
    #expect(attrs["terra.model.size_mb"] == AttributeValue.double(1024.0))
    #expect(attrs["terra.model.weight_file_count"] == AttributeValue.int(3))
    #expect(attrs["terra.model.format"] == AttributeValue.string("compiled_model"))
  }

  @Test("totalMB computation")
  func totalMBComputation() {
    let size = ModelSizeDetector.ModelSize(
      totalBytes: 52_428_800,  // 50 MB
      weightFileCount: 1,
      format: .compiledModel
    )
    #expect(size.totalMB == 50.0)
  }
}
