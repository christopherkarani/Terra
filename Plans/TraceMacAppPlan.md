# Trace Mac App Plan

Status: Immutable after creation

## Goals
- Deliver a new native AppKit macOS app that visualizes traces from live OTLP traffic.
- Provide a polished, production-grade UI that makes it easy to explore trace timelines, spans, and attributes.
- Integrate cleanly with existing `TerraTraceKit` models/renderers and `TraceStore` actor.
- Run on macOS 12+ as a SwiftPM-built app (no Xcode project requirement).

## Constraints
- Swift 6.2, Apple-grade engineering rigor.
- Strict TDD using Swift Testing framework (XCTest only if unavoidable).
- Use AppKit (not SwiftUI) for the app UI.
- Live OTLP only for v1 (no persisted trace import/export unless explicitly added later).
- No existing AppKit target in the repo; must be added via SwiftPM.
- Prefer value types and `Sendable` enforcement; avoid `Any`/type erasure.
- `TraceStore` is an actor and must remain the concurrency boundary.

## Non-Goals (v1)
- Persisted trace storage, import/export, or offline analysis.
- Multi-window or distributed collaboration.
- Advanced filtering/query language beyond basic UI filters.
- Trace sampling, aggregation, or heavy analytics beyond display.
- SwiftUI-based UI.

## Architecture Decisions
- App target: Add a SwiftPM executable target `TraceMacApp` using `AppKit` with `@main` entry point and `NSApplication`.
- Model source: Use existing `TerraTraceKit` trace models; no new model layer.
- Data flow:
  - `OTLPHTTPServer` receives live OTLP traffic and feeds `TraceStore`.
  - `TraceStore` exposes async APIs for snapshots and change streams (new if needed).
  - UI pulls snapshots on demand and subscribes to changes via async sequence or polling.
- Concurrency:
  - UI uses `MainActor` view models.
  - All trace mutation and ingestion happens inside `TraceStore` actor.
  - Use structured concurrency only; no shared mutable state.
- UI layering:
  - AppKit view controllers + custom views for timeline and span list.
  - Renderer reuse: adapt existing `TerraTraceKit` renderers for timeline drawing (NSView-backed).
  - UI state is separate from domain models via lightweight view models.
- Live-only:
  - App starts OTLP HTTP server automatically at launch.
  - Optional preferences screen for port selection (if required by existing server API).
- Testing:
  - View model logic is unit-tested in Swift Testing.
  - Renderer logic tested with deterministic inputs (no pixel tests in v1).
  - Actor interactions tested via async tests.

## Detailed To-Do List

### 1) Context and Codebase Survey
- Identify existing `TerraTraceKit` models, renderer APIs, and current usage patterns.
- Inspect `TraceStore` actor public API for snapshot/change capability.
- Inspect `OTLPHTTPServer` startup/configuration and lifecycle.
- Confirm SwiftPM configuration and any existing executable targets.

### 2) App Target and Entry Point
- Add SwiftPM executable target `TraceMacApp`.
- Implement `@main` App entry with `NSApplication` + `NSApplicationDelegate`.
- Create `AppCoordinator` to assemble core services (`TraceStore`, `OTLPHTTPServer`).
- Start OTLP server on launch; handle graceful shutdown.

### 3) Data Layer Adapters
- Define `TraceSnapshot` projection if needed for UI (immutable structs).
- Create `TraceStoreAdapter` or `TraceViewModel` that:
  - Pulls snapshots on demand.
  - Subscribes to changes (async stream or timer-driven refresh).
  - Provides selection state for trace/span.
- Ensure all types are `Sendable` where appropriate.

### 4) UI Architecture (AppKit)
- Window layout:
  - Left: Trace list (table view) with summary fields.
  - Center: Timeline view for selected trace (custom NSView).
  - Right: Span detail inspector (table/outline for attributes).
- Implement:
  - `TraceListViewController` (NSTableView data source).
  - `TraceTimelineView` (custom NSView using renderer).
  - `SpanDetailViewController`.
- Use `NSSplitViewController` for layout.
- Add toolbar for basic filters and search.

### 5) Renderer Integration
- Wrap existing renderer APIs into `TraceTimelineView`.
- Map selected trace data to renderer input.
- Ensure rendering on main thread with minimal allocations.

### 6) Tests (Mandatory, Test-First)
- Add Swift Testing targets for:
  - `TraceViewModel` selection and snapshot refresh behavior.
  - `TraceStore` integration tests with sample OTLP payloads (if test hooks exist).
  - Renderer adapter logic (mapping correctness).
- Write failing tests first before implementation.

### 7) Polished UI Pass
- Typography and spacing consistent with AppKit.
- Color palette for timeline and span states.
- Empty state and loading indicators.
- Basic keyboard navigation (up/down in trace list, enter to focus).

### 8) Documentation
- App overview in `README` or docs folder.
- Document OTLP port and how to point SDKs at it.
- Doc comments for any public API additions.

## Task to Agent Mapping

### Context and Research Agent
- Survey `TerraTraceKit` models/renderers.
- Summarize `TraceStore` and `OTLPHTTPServer` capabilities and APIs.

### Planning Agent
- Produce immutable plan and task breakdown.

### Implementation Agent
- Create new SwiftPM AppKit executable target.
- Implement `AppCoordinator`, `TraceViewModel`, and AppKit UI controllers/views.
- Integrate renderers.

### Test Agent
- Write Swift Testing tests for view model, store integration, renderer mapping.

### Code Review Agents
- Review plan compliance and API safety.
- Review concurrency usage, `Sendable`, and actor boundaries.
- Review UI integration and performance assumptions.

### Fix and Gap Agent
- Address review findings and missing tests.

## Assumptions
- `OTLPHTTPServer` can be started programmatically with a known port.
- `TraceStore` can provide either snapshots or an async change feed, or can be extended minimally.
- Existing renderers can be adapted to AppKit drawing without redesign.

## Risks
- Renderer APIs may be UIKit or SwiftUI oriented; adaptation may require a wrapper layer.
- `TraceStore` may not yet expose a change stream; may require non-trivial extension.
- Live OTLP ingestion volume could cause UI updates to stutter if refresh is too frequent.

## Exit Criteria
- App launches on macOS 12+ and starts OTLP server.
- Live traces appear in UI within seconds of ingestion.
- Timeline and span detail views update correctly on selection.
- All tests pass, and UI remains responsive under moderate trace load.
