# Terra: Unused Data Sources Audit

> Generated: 2026-02-21
> Scope: `Sources/TraceMacApp/` (72 Swift files, 290+ declarations)

---

## 1. Unused AppState Properties & Methods

### Properties

| Property | File | Line | Type | Status | Notes |
|----------|------|------|------|--------|-------|
| `openClawTransparentModeLastMessage` | `ViewModels/AppState.swift` | 117 | `String?` | WRITE-ONLY | Set in `toggleOpenClawTransparentMode()` but never read by any view |
| `streamingController` | `ViewModels/AppState.swift` | 116 | `FlowGraphStreamingController?` (private) | UNUSED | Assigned in `selectTrace()` but never read |
| `requestedTraceFileCount` | `ViewModels/AppState.swift` | 19 | `Int` (private) | WRITE-ONLY | Written in `loadTraces()`, `loadMoreTraces()`, `init()` but never read externally |
| `_spanDetailViewModel` | `ViewModels/AppState.swift` | 261 | `SpanDetailViewModel?` (private) | UNUSED | Backing store for computed property that is itself unused |

### Computed Properties

| Property | File | Lines | Status | Notes |
|----------|------|-------|--------|-------|
| `tracePageSizeSetting` | `ViewModels/AppState.swift` | 186-189 | UNUSED | Never accessed from any file |
| `isUsingOpenClawDiagnosticsDirectory` | `ViewModels/AppState.swift` | 255-258 | UNUSED | Only consumed internally by other unused code |
| `spanDetailViewModel` | `ViewModels/AppState.swift` | 263-275 | UNUSED | Never accessed outside AppState |
| `openClawTransparentModeStatusText` | `ViewModels/AppState.swift` | 244-249 | UNUSED | Reads `openClawTransparentModeLastMessage` but is itself never consumed |

### Methods

| Method | File | Line | Notes |
|--------|------|------|-------|
| `viewOllamaTraces()` | `ViewModels/AppState.swift` | 422 | Filters traces to Ollama runtime; never called from any UI |
| `openOpenClawApp()` | `ViewModels/AppState.swift` | 530 | Opens OpenClaw app via NSWorkspace; never invoked externally |

---

## 2. Unused Model Properties

### DashboardMetrics (9 unused latency percentiles)

All in `ViewModels/DashboardViewModel.swift`. These are computed in the `compute(from:)` method but never read by any view (KPIStripView, KPIGridPopoverView, or otherwise).

| Property | Line | Type | Notes |
|----------|------|------|-------|
| `e2eP50` | 17 | `TimeInterval` | End-to-end p50 latency; computed but never displayed |
| `e2eP95` | 18 | `TimeInterval` | End-to-end p95 latency; computed but never displayed |
| `e2eP99` | 19 | `TimeInterval` | End-to-end p99 latency; computed but never displayed |
| `promptEvalP50` | 20 | `TimeInterval` | Prompt eval p50 latency; computed but never displayed |
| `promptEvalP95` | 21 | `TimeInterval` | Prompt eval p95 latency; computed but never displayed |
| `promptEvalP99` | 22 | `TimeInterval` | Prompt eval p99 latency; computed but never displayed |
| `decodeP50` | 23 | `TimeInterval` | Decode p50 latency; computed but never displayed |
| `decodeP95` | 24 | `TimeInterval` | Decode p95 latency; computed but never displayed |
| `decodeP99` | 25 | `TimeInterval` | Decode p99 latency; computed but never displayed |

> **Note:** The main latency percentiles (`p50Duration`, `p95Duration`, `p99Duration`, `ttftP50`, `ttftP95`) ARE used. Only these sub-category breakdowns are orphaned.

---

## 3. Unused Enum Cases

| Enum | Case | File | Line | Notes |
|------|------|------|------|-------|
| `StatusKind` | `.ok` | `Components/StatusBadge.swift` | 5 | Only `.error` is instantiated in the codebase |
| `StatusKind` | `.warning` | `Components/StatusBadge.swift` | 7 | Never instantiated |
| `StatusKind` | `.pending` | `Components/StatusBadge.swift` | 8 | Never instantiated |
| `FlowNodeStatus` | `.pending` | `FlowGraph/FlowGraphNode.swift` | 47 | Only `.running`, `.completed`, `.error` are assigned |

---

## 4. Unused Functions & Methods

| Function | File | Line | Notes |
|----------|------|------|-------|
| `updateTracesDirectoryURL(_:)` | `TraceSplitViewController.swift` | 60 | Public method to update traces directory; never called |
| `statusFill(_:)` | `TraceUIStyle.swift` | 53 | Computes status color at 75% opacity; dead code from refactor |
| `selectNextSpan()` | `TraceViewModel.swift` | 72 | Span navigation; planned keyboard shortcut never wired up |
| `selectPreviousSpan()` | `TraceViewModel.swift` | 88 | Companion to above; also never wired up |
| `markerCompactionStats(...)` | `Timeline/TraceTimelineCanvasView.swift` | 772 | Debug diagnostic function; never called |

---

## 5. Unused Views

| View | File | Notes |
|------|------|-------|
| `KPICardView` | `Dashboard/KPICardView.swift` | Entire file is dead code. Replaced by `KPIGridPopoverView` (alias `KPICardsView` exists but is also unused) |

---

## 6. Unused Type Aliases

| Alias | File | Line | Notes |
|-------|------|------|-------|
| `PillButtonStyle` | `Theme/DashboardButtonStyle.swift` | 89 | Maps to `PrimaryButtonStyle`; marked "legacy" but never referenced |
| `AccentButtonStyle` | `Theme/DashboardButtonStyle.swift` | 90 | Maps to `PrimaryButtonStyle`; marked "legacy" but never referenced |
| `KPICardsView` | `Dashboard/KPICardsView.swift` | 94 | Maps to `KPIGridPopoverView`; never referenced |

---

## 7. Unused DashboardTheme Tokens

### Colors

| Token | File | Line | Notes |
|-------|------|------|-------|
| `borderSubtle` | `Theme/DashboardTheme.swift` | 24 | Defined but never referenced in any view |
| `warningBackground` | `Theme/DashboardTheme.swift` | 49 | Defined but never referenced in any view |
| `activeBackground` | `Theme/DashboardTheme.swift` | 51 | Defined but never referenced in any view |

### Fonts

| Token | File | Line | Notes |
|-------|------|------|-------|
| `rowSubtitle` | `Theme/DashboardTheme.swift` | 102 | Defined but never referenced |
| `codeLarge` | `Theme/DashboardTheme.swift` | 106 | Defined but never referenced |
| `codeSmall` | `Theme/DashboardTheme.swift` | 107 | Defined but never referenced |

### Shadows

| Token | File | Lines | Notes |
|-------|------|-------|-------|
| `Shadows.sm` | `Theme/DashboardTheme.swift` | 141 | Defined but never referenced |
| `Shadows.md` | `Theme/DashboardTheme.swift` | 143 | Used only in `FlowGraphControls.swift` — verify if still needed |
| `Shadows.lg` | `Theme/DashboardTheme.swift` | 145 | Defined but never referenced |

---

## 8. Unused Imports

| File | Import | Notes |
|------|--------|-------|
| `SpanInspector/SpanDetailView.swift` | `import OpenTelemetrySdk` | No OTel SDK types used directly in file |
| `SpanInspector/SpanLinksTable.swift` | `import OpenTelemetryApi` | No OTel API types used directly in file |
| `SpanInspector/SpanTreeRowView.swift` | `import OpenTelemetrySdk` | No OTel SDK types used directly in file |
| `SpanInspector/SpanInspectorView.swift` | `import OpenTelemetrySdk` | No OTel SDK types used directly in file |

---

## 9. Duplicate Definitions

| Type | Location 1 | Location 2 | Notes |
|------|-----------|-----------|-------|
| `CommandResult` (private struct) | `OpenClawTransparentModeManager.swift:124` | `ViewModels/AppState.swift:782` | Identical struct defined in two files; should be consolidated |

---

## 10. Potentially Orphaned Files

| File | Type Defined | Notes |
|------|-------------|-------|
| `TraceTimelineHitTester.swift` | `TraceTimelineHitTester` | Struct defined but no references found in any other file |
| `Dashboard/KPICardView.swift` | `KPICardView` | Entire view is unused; superseded by `KPIGridPopoverView` |

---

## Summary

| Category | Count |
|----------|-------|
| Unused AppState properties | 4 |
| Unused AppState computed properties | 4 |
| Unused AppState methods | 2 |
| Unused DashboardMetrics properties | 9 |
| Unused enum cases | 4 |
| Unused functions/methods | 5 |
| Unused views | 1 |
| Unused type aliases | 3 |
| Unused theme tokens | 8 |
| Unused imports | 4 |
| Duplicate definitions | 1 |
| Potentially orphaned files | 2 |
| **Total unused data sources** | **47** |
