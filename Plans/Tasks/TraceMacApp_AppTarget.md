Prompt:
Add a SwiftPM executable target named TraceMacApp using AppKit, with @main entry and NSApplication lifecycle. Implement AppCoordinator that owns TraceStore and OTLPHTTPServer and starts/stops the server.

Goal:
Create a runnable macOS 12+ AppKit app target that launches and starts the OTLP server cleanly.

Task Breakdown:
- Update Package.swift to add an executable target TraceMacApp and any required dependencies.
- Add @main entry point with NSApplication and NSApplicationDelegate.
- Implement AppCoordinator for service wiring and lifecycle.
- Ensure graceful shutdown on app termination.
- Keep all new types internal unless public is required.

Expected Output:
- New TraceMacApp target in Package.swift.
- App entry point and coordinator implementation files under Sources/TraceMacApp/.
- App launches without runtime errors.
