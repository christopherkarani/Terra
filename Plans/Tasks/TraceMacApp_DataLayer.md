Prompt:
Create a UI-facing data layer for the Mac app: TraceSnapshot projection (if needed) and a MainActor view model that retrieves snapshots from TraceStore and publishes selection state. Support change updates via async sequence or polling.

Goal:
Provide a minimal, Sendable-safe data adapter between TraceStore and AppKit UI.

Task Breakdown:
- Define immutable snapshot structs if TerraTraceKit types are too heavy for UI.
- Implement TraceViewModel (MainActor) with snapshot refresh and selection handling.
- Wire subscription to TraceStore updates (async stream or periodic refresh).
- Ensure concurrency boundaries are respected (TraceStore actor only for mutation/reads).
- Add doc comments if any public APIs are introduced.

Expected Output:
- New data layer types under Sources/TraceMacApp/ (or appropriate module).
- Clean Sendable usage and MainActor isolation.
