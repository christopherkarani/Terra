import Foundation

extension Terra {
  @TaskLocal static var agentContext: AgentContext?

  final class AgentContext: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var toolsUsed: Set<String> = []
    private(set) var modelsUsed: Set<String> = []
    private(set) var inferenceCount: Int = 0
    private(set) var toolCallCount: Int = 0

    func recordTool(_ name: String) {
      lock.lock()
      toolsUsed.insert(name)
      toolCallCount += 1
      lock.unlock()
    }

    func recordModel(_ name: String) {
      lock.lock()
      modelsUsed.insert(name)
      inferenceCount += 1
      lock.unlock()
    }

    func snapshot() -> Snapshot {
      lock.lock()
      let snapshot = Snapshot(
        toolsUsed: toolsUsed,
        modelsUsed: modelsUsed,
        inferenceCount: inferenceCount,
        toolCallCount: toolCallCount
      )
      lock.unlock()
      return snapshot
    }

    struct Snapshot: Sendable {
      let toolsUsed: Set<String>
      let modelsUsed: Set<String>
      let inferenceCount: Int
      let toolCallCount: Int
    }
  }
}
