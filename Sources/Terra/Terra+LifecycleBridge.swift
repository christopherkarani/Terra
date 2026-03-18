extension Terra {
  package static func _markRuntimeRunningForLifecycle() {
    Runtime.shared.markRunning()
  }
}
