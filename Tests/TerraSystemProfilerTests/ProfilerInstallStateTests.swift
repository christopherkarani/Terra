import Testing
@testable import TerraSystemProfiler

@Suite("ProfilerInstallState")
struct ProfilerInstallStateTests {

  private enum TestMarker {}

  @Test("starts uninstalled")
  func startsUninstalled() {
    let state = ProfilerInstallState<TestMarker>()
    #expect(!state.isInstalled)
  }

  @Test("install transitions to installed")
  func installTransitions() {
    let state = ProfilerInstallState<TestMarker>()
    state.install()
    #expect(state.isInstalled)
  }

  @Test("multiple installs are idempotent")
  func multipleInstalls() {
    let state = ProfilerInstallState<TestMarker>()
    state.install()
    state.install()
    state.install()
    #expect(state.isInstalled)
  }

  @Test("concurrent installs are safe")
  func concurrentInstalls() async {
    let state = ProfilerInstallState<TestMarker>()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask { state.install() }
      }
    }
    #expect(state.isInstalled)
  }
}
