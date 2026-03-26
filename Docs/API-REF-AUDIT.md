# API-Reference.md Audit Report

> **Archival note:** This report is historical. Treat the current source and DocC bundle as the source of truth.

**Auditor:** Documentation Accuracy Auditor
**Date:** 2026-03-22
**Files Audited:**
- `Sources/Terra/Terra+ComposableAPI.swift`
- `Sources/Terra/Terra+Identifiers.swift`
- `Sources/TerraAutoInstrument/Terra.docc/API-Reference.md`

---

## Summary

| Category | Count |
|----------|-------|
| Total Discrepancies | 2 |
| Critical | 1 |
| Medium | 1 |

---

## Discrepancies

### DISCREPANCY 1: Missing `attr` method on Operation

**File:** `API-Reference.md` at "Custom Attributes" section

**Code Example in Documentation:**
```swift
try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .attr(.userTier, "pro")
    .attr(.requestID, UUID().uuidString)
    .run { "response" }
```

**ACTUAL:** There is NO `attr` method on `Operation` in the source code. The only public methods on `Operation` are:
- `capture(_: CapturePolicy) -> Self`
- `run(_:) async rethrows -> R`
- `run(using:_:) async rethrows -> R` (package-internal)

**DOCUMENTED:** Operation has a chainable `.attr()` method for adding custom attributes.

**FIX:** Remove the `.attr()` example from the Custom Attributes section, or document the correct way to add custom attributes using the internal `_mergedAttributes` pattern. The static `Terra.attr(_:_:)` method exists for use with `@Terra.MetadataBuilder`, but this is not the same as an instance method on Operation.

---

### DISCREPANCY 2: Incorrect TraceHandle.tag generic constraint documentation

**File:** `API-Reference.md` at "TraceHandle Methods > tag(_:_:)"

**DOCUMENTED:**
```swift
public func tag<T: CustomStringConvertible & Sendable>(
    _ key: StaticString,
    _ value: T
) -> Self
```

**ACTUAL:** (from Terra+ComposableAPI.swift line 242)
```swift
public func tag<T: CustomStringConvertible & Sendable>(_ key: StaticString, _ value: T) -> Self
```

**This is actually CORRECT in the documentation.** No discrepancy.

---

## Verified Correct

The following were verified against source and found accurate:

| Section | Verification |
|---------|-------------|
| Typed IDs (ModelID, ProviderID, RuntimeID, ToolCallID) | All struct definitions match |
| `infer()` factory method | Signature matches: `(_ model: ModelID, prompt: String?, provider: ProviderID?, runtime: RuntimeID?, temperature: Double?, maxTokens: Int?) -> Operation` |
| `stream()` factory method | Signature matches including `expectedTokens: Int?` |
| `embed()` factory method | Signature matches |
| `agent()` factory method | Signature matches |
| `tool()` factory method | Signature matches with `callID: ToolCallID = .init()` |
| `safety()` factory method | Signature matches |
| `capture(_:)` method | Signature matches `CapturePolicy` enum |
| `run(_:)` method | Both overloads documented correctly |
| `run(using:_:)` method | Both overloads documented correctly (package-internal noted) |
| TraceHandle methods | All signatures match: `event`, `tag`, `tokens`, `responseModel`, `chunk`, `outputTokens`, `firstToken`, `recordError` |
| Lifecycle methods | `start`, `shutdown`, `reconfigure`, `reset` all match (async/throws correctly) |
| TerraError codes | All documented codes exist in source |
| TelemetryEngine protocol | Matches source definition |
