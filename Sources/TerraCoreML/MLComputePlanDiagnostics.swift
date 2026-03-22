#if canImport(CoreML)
import CoreML
import Foundation
import OpenTelemetryApi
import TerraCore
import TerraSystemProfiler

package struct TerraCoreMLComputePlanOperationEstimate: Codable, Hashable, Sendable {
  package let identifier: String
  package let kind: String
  package let preferredDevice: String
  package let supportedDevices: [String]
}

package struct TerraCoreMLComputePlanSummary: Codable, Hashable, Sendable, TelemetryAttributeConvertible {
  package enum CaptureStatus: String, Codable, Hashable, Sendable {
    case captured
    case unsupportedOS = "unsupported_os"
    case loadFailed = "load_failed"
    case unsupportedStructure = "unsupported_structure"
  }

  package let captureStatus: CaptureStatus
  package let modelStructure: String
  package let estimatedPrimaryDevice: String
  package let supportedDevices: [String]
  package let nodeCount: Int
  package let captureDurationMS: Double
  package let operationEstimates: [TerraCoreMLComputePlanOperationEstimate]
  package let errorType: String?

  package var telemetryAttributes: [String: AttributeValue] {
    var attributes: [String: AttributeValue] = [
      TerraCoreML.Keys.computePlanCaptureStatus: .string(captureStatus.rawValue),
      TerraCoreML.Keys.computePlanModelStructure: .string(modelStructure),
      TerraCoreML.Keys.computePlanEstimatedPrimaryDevice: .string(estimatedPrimaryDevice),
      TerraCoreML.Keys.computePlanSupportedDevices: .string(supportedDevices.joined(separator: ",")),
      TerraCoreML.Keys.computePlanNodeCount: .int(nodeCount),
      TerraCoreML.Keys.computePlanCaptureDurationMs: .double(captureDurationMS),
    ]
    attributes.merge(
      Terra.ExecutionRouteEvidence(
        estimatedPrimary: estimatedPrimaryDevice == "unknown" ? nil : estimatedPrimaryDevice,
        supported: supportedDevices,
        captureMode: .planEstimated,
        confidence: captureStatus == .captured ? .medium : .low
      ).telemetryAttributes
    ) { _, newValue in newValue }

    if !operationEstimates.isEmpty,
       let data = try? JSONEncoder().encode(operationEstimates),
       let serialized = String(data: data, encoding: .utf8)
    {
      attributes[TerraCoreML.Keys.computePlanEstimatedOperations] = .string(serialized)
    }

    if let errorType {
      attributes[TerraCoreML.Keys.computePlanErrorType] = .string(errorType)
    }

    return attributes
  }
}

package enum MLComputePlanDiagnostics {
  package static func captureSummary(
    contentsOf url: URL,
    configuration: MLModelConfiguration
  ) async -> TerraCoreMLComputePlanSummary {
    let startedAt = ContinuousClock.now

    guard #available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *) else {
      return .init(
        captureStatus: .unsupportedOS,
        modelStructure: "unsupported",
        estimatedPrimaryDevice: "unknown",
        supportedDevices: [],
        nodeCount: 0,
        captureDurationMS: elapsedMilliseconds(since: startedAt),
        operationEstimates: [],
        errorType: nil
      )
    }

    do {
      let computePlan = try await MLComputePlan.load(contentsOf: url, configuration: configuration)
      let summary = summarize(computePlan)
      return .init(
        captureStatus: summary.captureStatus,
        modelStructure: summary.modelStructure,
        estimatedPrimaryDevice: summary.estimatedPrimaryDevice,
        supportedDevices: summary.supportedDevices,
        nodeCount: summary.nodeCount,
        captureDurationMS: elapsedMilliseconds(since: startedAt),
        operationEstimates: summary.operationEstimates,
        errorType: summary.errorType
      )
    } catch {
      return .init(
        captureStatus: .loadFailed,
        modelStructure: "unsupported",
        estimatedPrimaryDevice: "unknown",
        supportedDevices: [],
        nodeCount: 0,
        captureDurationMS: elapsedMilliseconds(since: startedAt),
        operationEstimates: [],
        errorType: String(reflecting: type(of: error))
      )
    }
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  package static func summarize(_ computePlan: MLComputePlan) -> TerraCoreMLComputePlanSummary {
    switch computePlan.modelStructure {
    case .program(let program):
      return buildSummary(
        modelStructure: "program",
        estimates: collectOperationEstimates(from: program, computePlan: computePlan, prefix: "program")
      )
    case .neuralNetwork(let neuralNetwork):
      return buildSummary(
        modelStructure: "neural_network",
        estimates: collectLayerEstimates(from: neuralNetwork, computePlan: computePlan, prefix: "neural_network")
      )
    case .pipeline(let pipeline):
      return buildSummary(
        modelStructure: "pipeline",
        estimates: collectPipelineEstimates(from: pipeline, computePlan: computePlan, prefix: "pipeline")
      )
    case .unsupported:
      return .init(
        captureStatus: .unsupportedStructure,
        modelStructure: "unsupported",
        estimatedPrimaryDevice: "unknown",
        supportedDevices: [],
        nodeCount: 0,
        captureDurationMS: 0,
        operationEstimates: [],
        errorType: nil
      )
    @unknown default:
      return .init(
        captureStatus: .unsupportedStructure,
        modelStructure: "unsupported",
        estimatedPrimaryDevice: "unknown",
        supportedDevices: [],
        nodeCount: 0,
        captureDurationMS: 0,
        operationEstimates: [],
        errorType: nil
      )
    }
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  package static func deviceLabel(_ device: MLComputeDevice) -> String {
    switch device {
    case .cpu:
      return "cpu"
    case .gpu:
      return "gpu"
    case .neuralEngine:
      return "ane"
    @unknown default:
      return "unknown"
    }
  }

  private static func elapsedMilliseconds(since startedAt: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - startedAt
    return Double(elapsed.components.seconds) * 1000
      + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func buildSummary(
    modelStructure: String,
    estimates: [TerraCoreMLComputePlanOperationEstimate]
  ) -> TerraCoreMLComputePlanSummary {
    let preferredDevices = Set(estimates.map(\.preferredDevice).filter { $0 != "unknown" })
    let supportedDevices = Set(estimates.flatMap(\.supportedDevices))

    let estimatedPrimaryDevice: String
    switch preferredDevices.count {
    case 0:
      estimatedPrimaryDevice = "unknown"
    case 1:
      estimatedPrimaryDevice = preferredDevices.first ?? "unknown"
    default:
      estimatedPrimaryDevice = "mixed"
    }

    return .init(
      captureStatus: .captured,
      modelStructure: modelStructure,
      estimatedPrimaryDevice: estimatedPrimaryDevice,
      supportedDevices: supportedDevices.sorted(),
      nodeCount: estimates.count,
      captureDurationMS: 0,
      operationEstimates: estimates,
      errorType: nil
    )
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func collectPipelineEstimates(
    from pipeline: MLModelStructure.Pipeline,
    computePlan: MLComputePlan,
    prefix: String
  ) -> [TerraCoreMLComputePlanOperationEstimate] {
    zip(pipeline.subModelNames, pipeline.subModels).flatMap { name, subModel in
      collectEstimates(from: subModel, computePlan: computePlan, prefix: "\(prefix).\(name)")
    }
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func collectEstimates(
    from structure: MLModelStructure,
    computePlan: MLComputePlan,
    prefix: String
  ) -> [TerraCoreMLComputePlanOperationEstimate] {
    switch structure {
    case .program(let program):
      return collectOperationEstimates(from: program, computePlan: computePlan, prefix: prefix)
    case .neuralNetwork(let neuralNetwork):
      return collectLayerEstimates(from: neuralNetwork, computePlan: computePlan, prefix: prefix)
    case .pipeline(let pipeline):
      return collectPipelineEstimates(from: pipeline, computePlan: computePlan, prefix: prefix)
    case .unsupported:
      return []
    @unknown default:
      return []
    }
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func collectOperationEstimates(
    from program: MLModelStructure.Program,
    computePlan: MLComputePlan,
    prefix: String
  ) -> [TerraCoreMLComputePlanOperationEstimate] {
    program.functions.keys.sorted().flatMap { functionName -> [TerraCoreMLComputePlanOperationEstimate] in
      guard let function = program.functions[functionName] else { return [] }
      return collectOperationEstimates(
        from: function.block,
        computePlan: computePlan,
        prefix: "\(prefix).\(functionName)"
      )
    }
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func collectOperationEstimates(
    from block: MLModelStructure.Program.Block,
    computePlan: MLComputePlan,
    prefix: String
  ) -> [TerraCoreMLComputePlanOperationEstimate] {
    var estimates: [TerraCoreMLComputePlanOperationEstimate] = []

    for (index, operation) in block.operations.enumerated() {
      if let usage = computePlan.deviceUsage(for: operation) {
        estimates.append(
          .init(
            identifier: "\(prefix).op\(index).\(operation.operatorName)",
            kind: "program_operation",
            preferredDevice: deviceLabel(usage.preferred),
            supportedDevices: usage.supported.map(deviceLabel).sorted()
          )
        )
      } else {
        estimates.append(
          .init(
            identifier: "\(prefix).op\(index).\(operation.operatorName)",
            kind: "program_operation",
            preferredDevice: "unknown",
            supportedDevices: []
          )
        )
      }

      for (nestedIndex, nestedBlock) in operation.blocks.enumerated() {
        estimates.append(
          contentsOf: collectOperationEstimates(
            from: nestedBlock,
            computePlan: computePlan,
            prefix: "\(prefix).op\(index).block\(nestedIndex)"
          )
        )
      }
    }

    return estimates
  }

  @available(macOS 14.4, iOS 17.4, tvOS 17.4, watchOS 10.4, *)
  private static func collectLayerEstimates(
    from neuralNetwork: MLModelStructure.NeuralNetwork,
    computePlan: MLComputePlan,
    prefix: String
  ) -> [TerraCoreMLComputePlanOperationEstimate] {
    neuralNetwork.layers.enumerated().map { index, layer in
      let usage = computePlan.deviceUsage(for: layer)
      return .init(
        identifier: "\(prefix).layer\(index).\(layer.name)",
        kind: "neural_network_layer:\(layer.type)",
        preferredDevice: usage.map { deviceLabel($0.preferred) } ?? "unknown",
        supportedDevices: usage.map { $0.supported.map(deviceLabel).sorted() } ?? []
      )
    }
  }
}
#endif
