# TraceMacApp Plan (Immutable)

## Goals
- Build a polished macOS AppKit trace viewer with three labeled feature areas:
  - A: Trace list + filter/search.
  - B: Timeline/graph view of spans.
  - C: Span detail panel (attributes, events, links).
- Provide clear trace linking and highlight important areas (critical spans, errors, long durations).
- Read trace files from Terra persistence traces folder.
- Correct decoding of trace files (comma-separated JSON arrays of `SpanData`).

## Constraints
- No existing UI/app sources; only an Xcode project exists.
- No `TerraTraceKit` target available.
- Persistence format: file name is milliseconds since reference date.
- File contents are comma-separated JSON arrays of `SpanData`.
- Decode by wrapping data with `[` and `null]` before decoding.
- Tests-first using Swift Testing; no UI tests.
- Prioritize correctness, then type safety, then API clarity, then performance.

## Non-Goals
- No UI automation / snapshot tests.
- No remote trace ingestion or networking.
- No changes to Terra persistence format.
- No advanced performance optimization beyond reasonable AppKit practice.
- No SwiftUI; AppKit only.

## Architecture Decisions
- Core layers:
  - TracePersistence: file location, reading, decoding.
  - TraceModel: aggregate trace data and computed metadata.
  - TraceViewModel: list/filter/timeline/detail view models.
  - AppKit UI: split view with list, timeline, detail.
- Data flow: file discovery -> decode -> Trace objects -> view models -> views.
- Use simple callbacks/notifications for UI updates; avoid extra dependencies.

## Task Breakdown
1. Test scaffolding + model contracts (Swift Testing).
2. Persistence access layer (locator, reader, decoder) + tests.
3. Model assembly + tests.
4. View model layer + tests.
5. AppKit UI (split view, list, timeline, detail) wiring.
6. Integration + manual QA checklist.

## Task -> Agent Mapping
- Task decomposition agent: create .md task files from this plan.
- Test-first agents: T1 (decoder/model), T2 (persistence), T3 (view models).
- Implementation agents: I1 (persistence), I2 (model), I3 (view models), I4 (AppKit UI).
- Review agents: 1 per task; 2 for UI integration.
- Fix/gap agent as needed.

## Legacy Notes

- Earlier implementation direction (now superseded) focused on live OTLP ingestion in the UI with `TraceStore` snapshots and refresh loops, while maintaining AppKit-only architecture and strict `Sendable` actor boundaries.
