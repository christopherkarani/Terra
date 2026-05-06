import Foundation
import OpenTelemetryApi

/// A single thermal state measurement at a point in time.
///
/// Use ``ThermalMonitor/sample()`` to capture the current thermal state,
/// or use ``ThermalMonitor/profile(start:end:)`` to compute a full profile
/// over a time window.
public struct ThermalSample: Sendable {
  /// The process thermal state at the time of sampling.
  public let state: ProcessInfo.ThermalState

  /// The wall-clock time when the sample was captured.
  public let timestamp: Date

  /// Creates a new thermal sample.
  ///
  /// - Parameters:
  ///   - state: The `ProcessInfo.ThermalState` at capture time.
  ///   - timestamp: The time of capture. Defaults to `Date()`.
  public init(state: ProcessInfo.ThermalState, timestamp: Date = Date()) {
    self.state = state
    self.timestamp = timestamp
  }
}

/// Aggregated thermal profile over a time window.
///
/// ``ThermalProfile`` records the initial and final thermal states, the peak
/// state reached, total elapsed time, and time spent in a throttled state
/// (serious or critical). Attach to inference traces via ``TelemetryAttributeConvertible``.
///
/// - SeeAlso: ``ThermalMonitor/profile(start:end:)``
public struct ThermalProfile: Sendable, TelemetryAttributeConvertible {
  /// The thermal state at the start of the profiling window.
  public let startState: ProcessInfo.ThermalState

  /// The thermal state at the end of the profiling window.
  public let endState: ProcessInfo.ThermalState

  /// The highest thermal state reached during the window.
  public let peakState: ProcessInfo.ThermalState

  /// Total elapsed time in seconds.
  public let durationSeconds: Double

  /// Time spent in a throttled state (serious or critical), in seconds.
  public let timeInThrottledSeconds: Double

  /// Converts the thermal profile into OpenTelemetry span attributes.
  ///
  /// Produces:
  /// - `terra.thermal.state` (string): Thermal state at end of window.
  /// - `terra.thermal.peak_state` (string): Highest state reached.
  /// - `terra.thermal.time_throttled_s` (double): Seconds spent in throttled state.
  public var telemetryAttributes: [String: AttributeValue] {
    [
      "terra.thermal.state": .string(ThermalMonitor.stateLabel(endState)),
      "terra.thermal.peak_state": .string(ThermalMonitor.stateLabel(peakState)),
      "terra.thermal.time_throttled_s": .double(timeInThrottledSeconds),
    ]
  }
}

/// Monitors the device thermal state and produces thermal profiles.
///
/// Thermal throttling can significantly impact model inference latency. Use
/// ``ThermalMonitor`` to record thermal state transitions and correlate them
/// with inference performance in your traces.
///
/// ## Usage
/// ```swift
/// ThermalMonitor.install()
/// let start = ThermalMonitor.sample()
/// // ... run inference ...
/// let end = ThermalMonitor.sample()
/// let profile = ThermalMonitor.profile(start: start, end: end)
/// ```
///
/// ## Continuous Sampling
///
/// On `install()`, ``ThermalMonitor`` registers an observer for
/// `ProcessInfo.thermalStateDidChangeNotification` and records every transition
/// into a bounded sliding-window buffer. ``profile(start:end:)`` then folds
/// any buffered transitions whose timestamp falls inside the window into the
/// peak computation. This catches transient spikes that begin and recover
/// between explicit ``sample()`` calls.
public enum ThermalMonitor {
  /// Maximum number of thermal transitions retained in the sliding-window buffer.
  ///
  /// Older transitions are evicted FIFO when the buffer is full. 256 is large
  /// enough to retain a long inference window's worth of state changes while
  /// bounding memory.
  package static let transitionBufferCapacity: Int = 256

  private static let store = ThermalTransitionStore(capacity: transitionBufferCapacity)

  /// Installs thermal monitoring hooks.
  ///
  /// Registers a `ProcessInfo.thermalStateDidChangeNotification` observer that
  /// records each transition into a thread-safe sliding-window buffer.
  /// Subsequent calls to ``profile(start:end:)`` consult the buffer to detect
  /// mid-window thermal spikes that would otherwise be missed by sampling alone.
  ///
  /// Calling `install()` multiple times is idempotent: only one observer is
  /// registered.
  public static func install() {
    store.install()
  }

  /// Returns `true` if thermal monitoring has been installed.
  public static var isInstalled: Bool {
    store.isInstalled
  }

  package static func reset() {
    store.reset()
  }

  /// Captures the current thermal state as a ``ThermalSample``.
  ///
  /// - Returns: A new `ThermalSample` with the current `ProcessInfo.thermalState`
  ///   and the current wall-clock time.
  public static func sample() -> ThermalSample {
    ThermalSample(state: ProcessInfo.processInfo.thermalState)
  }

  /// Returns a human-readable label for a `ProcessInfo.ThermalState`.
  ///
  /// - Parameter state: The thermal state to label.
  /// - Returns: One of `"nominal"`, `"fair"`, `"serious"`, `"critical"`, or `"unknown"`.
  public static func stateLabel(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  /// Computes a thermal profile between two samples.
  ///
  /// Peak state is the maximum of:
  /// - `start.state`
  /// - `end.state`
  /// - any buffered transitions recorded by the installed observer whose
  ///   timestamp lies in the closed interval `[start.timestamp, end.timestamp]`
  ///
  /// Throttled time is the duration the window spent at or above
  /// `.serious`. When the observer is installed, this is computed by
  /// integrating across the buffered transitions (treating each transition as
  /// a step change). When no transitions are buffered, the legacy heuristic
  /// applies: the entire window counts as throttled if either endpoint is
  /// `.serious`/`.critical`.
  ///
  /// - Parameters:
  ///   - start: The starting ``ThermalSample``.
  ///   - end: The ending ``ThermalSample``.
  /// - Returns: A ``ThermalProfile`` with start/end/peak states, duration, and
  ///   throttled time.
  public static func profile(start: ThermalSample, end: ThermalSample) -> ThermalProfile {
    let duration = max(0, end.timestamp.timeIntervalSince(start.timestamp))

    let windowStart = min(start.timestamp, end.timestamp)
    let windowEnd = max(start.timestamp, end.timestamp)
    let buffered = store.transitions(in: windowStart...windowEnd)

    // Peak: fold start, end, and all in-window buffered transitions.
    var peakRaw = max(start.state.rawValue, end.state.rawValue)
    for transition in buffered {
      peakRaw = max(peakRaw, transition.state.rawValue)
    }
    let peakState = ProcessInfo.ThermalState(rawValue: peakRaw) ?? end.state

    // Throttled time: if we have buffered transitions, integrate piecewise.
    // Otherwise fall back to the original endpoint heuristic.
    let throttledTime: Double
    if buffered.isEmpty {
      let isThrottled = start.state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        || end.state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
      throttledTime = isThrottled ? duration : 0
    } else {
      throttledTime = computeThrottledSeconds(
        startState: start.state,
        startTime: windowStart,
        endTime: windowEnd,
        transitions: buffered
      )
    }

    return ThermalProfile(
      startState: start.state,
      endState: end.state,
      peakState: peakState,
      durationSeconds: duration,
      timeInThrottledSeconds: throttledTime
    )
  }

  /// Integrates the time spent in throttled (`.serious` or `.critical`) state
  /// across the window, treating buffered transitions as step changes.
  private static func computeThrottledSeconds(
    startState: ProcessInfo.ThermalState,
    startTime: Date,
    endTime: Date,
    transitions: [ThermalTransition]
  ) -> Double {
    let throttleThreshold = ProcessInfo.ThermalState.serious.rawValue
    let sorted = transitions.sorted { $0.timestamp < $1.timestamp }

    var currentState = startState
    var cursor = startTime
    var throttled: Double = 0

    for transition in sorted {
      let segmentEnd = max(cursor, min(transition.timestamp, endTime))
      if currentState.rawValue >= throttleThreshold {
        throttled += segmentEnd.timeIntervalSince(cursor)
      }
      cursor = segmentEnd
      currentState = transition.state
    }

    if cursor < endTime {
      if currentState.rawValue >= throttleThreshold {
        throttled += endTime.timeIntervalSince(cursor)
      }
    }

    return max(0, throttled)
  }

  // MARK: - Test Hooks

  /// Test-only: appends a synthetic transition to the buffer without invoking
  /// the notification system. Used by tests to drive deterministic state
  /// changes that do not depend on the device actually heating up.
  package static func recordTransitionForTesting(
    state: ProcessInfo.ThermalState,
    timestamp: Date
  ) {
    store.append(.init(state: state, timestamp: timestamp))
  }

  /// Test-only: returns the current count of buffered transitions.
  package static func bufferedTransitionCountForTesting() -> Int {
    store.count
  }

  /// Test-only mirror of ``transitionBufferCapacity`` for explicit assertions.
  package static var transitionBufferCapacityForTesting: Int {
    transitionBufferCapacity
  }
}

// MARK: - Internal Store

/// A single thermal state transition observed at a point in time.
struct ThermalTransition: Sendable {
  let state: ProcessInfo.ThermalState
  let timestamp: Date
}

/// Thread-safe store of recent thermal transitions and the lifecycle of the
/// `ProcessInfo.thermalStateDidChangeNotification` observer.
///
/// Uses an `NSLock` to guard the bounded ring buffer, matching the existing
/// concurrency pattern in ``ProfilerInstallState``.
final class ThermalTransitionStore: @unchecked Sendable {
  private let lock = NSLock()
  private let capacity: Int
  private var buffer: [ThermalTransition] = []
  private var observer: NSObjectProtocol?
  private var _isInstalled = false

  init(capacity: Int) {
    self.capacity = capacity
    self.buffer.reserveCapacity(capacity)
  }

  var isInstalled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isInstalled
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return buffer.count
  }

  func install() {
    lock.lock()
    if _isInstalled {
      lock.unlock()
      return
    }
    _isInstalled = true
    lock.unlock()

    let observer = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      guard let self else { return }
      self.append(
        .init(state: ProcessInfo.processInfo.thermalState, timestamp: Date())
      )
    }

    lock.lock()
    self.observer = observer
    lock.unlock()
  }

  func reset() {
    lock.lock()
    let toRemove = observer
    observer = nil
    buffer.removeAll(keepingCapacity: true)
    _isInstalled = false
    lock.unlock()

    if let toRemove {
      NotificationCenter.default.removeObserver(toRemove)
    }
  }

  func append(_ transition: ThermalTransition) {
    lock.lock()
    defer { lock.unlock() }
    if buffer.count >= capacity {
      buffer.removeFirst()
    }
    buffer.append(transition)
  }

  /// Returns transitions whose timestamps fall inside the closed interval.
  /// O(window-size) — caller-bounded by buffer capacity.
  func transitions(in interval: ClosedRange<Date>) -> [ThermalTransition] {
    lock.lock()
    defer { lock.unlock() }
    return buffer.filter { interval.contains($0.timestamp) }
  }
}
