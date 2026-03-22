# DocC Articles Audit Report

**Auditor:** Documentation Accuracy Auditor
**Date:** 2026-03-22
**Articles Audited:**
- TerraCore.md
- CoreML-Integration.md
- FoundationModels.md
- Profiler-Integration.md
- Typed-IDs.md
- TerraError-Model.md
- Metadata-Builder.md

---

## Summary

| Article | Discrepancies |
|---------|---------------|
| TerraCore.md | 1 (Critical) |
| CoreML-Integration.md | 0 |
| FoundationModels.md | 1 (Medium) |
| Profiler-Integration.md | 0 |
| Typed-IDs.md | 0 |
| TerraError-Model.md | 0 |
| Metadata-Builder.md | 0 |
| **Total** | **2** |

---

## Discrepancies

---

### DISCREPANCY 1: TerraCore.md - Incorrect `.includeContent()` Method

**File:** `TerraCore.md` at "Content Capture" section (line ~46)

**DOCUMENTED:**
```swift
let resultWithContent = try await Terra
  .infer(Terra.ModelID("gpt-4o-mini"), prompt: "Hello")
  .includeContent()
  .run { "response" }
```

**ACTUAL:** The method `.includeContent()` does NOT exist on `Operation`. The correct API is `.capture(.includeContent)`:

```swift
let resultWithContent = try await Terra
  .infer(Terra.ModelID("gpt-4o-mini"), prompt: "Hello")
  .capture(.includeContent)
  .run { "response" }
```

**Source Verification:**
- `Terra+ComposableAPI.swift` line 366: `public func capture(_ policy: CapturePolicy) -> Self`
- No `includeContent()` method exists on `Operation`

**FIX:** Replace `.includeContent()` with `.capture(.includeContent)` in the code example.

---

### DISCREPANCY 2: FoundationModels.md - Incorrect `respond(to:promptCapture:)` Parameter Label

**File:** `FoundationModels.md` at "Content Capture" section (line ~93)

**DOCUMENTED:**
```swift
let debugResponse = try await session.respond(
  to: "Query",
  promptCapture: .includeContent  // Captures full prompt/response
)
```

**ACTUAL:** The actual method signature from `TerraTracedSession.swift` line 191 is:
```swift
public func respond(to prompt: String, promptCapture: Terra.CapturePolicy = .default) async throws -> String
```

The parameter label is correct (`promptCapture`), but the documentation says "Captures full prompt/response" which is misleading. With `.includeContent`, the content is captured **if** the privacy policy allows it. The `CapturePolicy` merely overrides the per-call capture setting, but privacy policy still governs what actually gets stored.

**Source Verification:**
- `TerraTracedSession.swift` line 191 confirms the signature
- The `promptCapture` parameter controls whether to bypass privacy policy for this specific call

**FIX:** Clarify the comment to say "Respects privacy policy when capturing" or note that `.includeContent` bypasses the privacy policy's opt-in requirement for this specific call.

---

## Articles Verified Correct

### CoreML-Integration.md
| Section | Status |
|---------|--------|
| MLModelConfiguration setup | Matches `MLComputeUnits` |
| Auto-instrumentation | Correct - enabled via feature flags |
| Metrics collection example | Correct API usage |
| Manual span creation | Correct `.infer()` usage |
| Span attributes | Accurate |

### Profiler-Integration.md
| Section | Status |
|---------|--------|
| TerraANEProfiler | Correct - uses `ANEHardwareProfiler` and `ANEProfilerSession` types |
| ANEHardwareMetrics fields | All documented fields exist |
| TerraMetalProfiler | Correct - `TerraMetalProfiler.install()` documented correctly |
| TerraSystemProfiler | Correct - `captureMemorySnapshot()` and `memoryDeltaAttributes` used correctly |
| TerraPowerProfiler | Correct - `PowerDomains` and `PowerMetricsCollector` types exist |
| Configuration examples | Correct OptionSet usage |

### Typed-IDs.md
| Section | Status |
|---------|--------|
| ID types listed | All 4 types exist: ModelID, ProviderID, RuntimeID, ToolCallID |
| Usage examples | Correct construction and parameter passing |

### TerraError-Model.md
| Section | Status |
|---------|--------|
| Error codes | All 6 codes exist in `Terra.TerraError.Code` |
| Handling pattern | Correct usage pattern with `TerraError` |

### Metadata-Builder.md
| Section | Status |
|---------|--------|
| TraceHandle methods | Correct - `event`, `tag`, `chunk`, `outputTokens`, `firstToken` |
| Note about tag() | Correct - values stored as strings |

### TerraCore.md (excluding DISCREPANCY 1)
| Section | Status |
|---------|--------|
| PrivacyPolicy levels | Correct - all 4 cases exist |
| RedactionStrategy | Correct documentation |
| LifecycleState | Correct - all 4 states |
| TelemetryEngine protocol | Correct |
| Configuration presets | Correct - quickstart, production, diagnostics |
| Features OptionSet | Correct |

---

## Cross-Reference: Public API Surface Not In Docs

The following public APIs exist in source but are NOT documented in any DocC article:

1. **`Terra.lifecycleState`** (property) - documented in API-Reference.md as `Terra/lifecycleState` (correct)
2. **`Terra.isRunning`** (property) - exists in `Terra+Lifecycle.swift` line 74
3. **`Terra._lifecycleState`** (private static) - internal, correctly not documented

---

## Notes

1. **Terra.PrivacyPolicy vs Terra.Privacy**: The source has two privacy-related types:
   - `Terra.PrivacyPolicy` (public enum) - documented and used in Configuration
   - `Terra.Privacy` (internal struct) - used internally by the runtime

2. **Configuration.privacy property**: Correctly typed as `Terra.PrivacyPolicy` per `Terra+PrivacyV3.swift` and `Terra+Start.swift` line 177.

3. **TracedSession**: `TerraTracedSession` is correctly documented in FoundationModels.md and exists in `TerraFoundationModels/TerraTracedSession.swift`.
