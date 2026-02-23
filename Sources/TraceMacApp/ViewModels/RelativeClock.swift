import SwiftUI

/// Shared clock that ticks every 10 seconds, replacing per-row Timer instances.
/// Inject via `.environment(relativeClock)` — views read `clock.tick` to trigger
/// relative-time recomputation without individual timer subscriptions.
@Observable
@MainActor
final class RelativeClock {
    private(set) var tick: UInt = 0
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.tick &+= 1
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
