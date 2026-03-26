# Terra Documentation Audit Report

> **Archival note:** This report is historical. Treat the current source and DocC bundle as the source of truth.

## Critical Discrepancies Found

### Issue #1: `.attr()` Method Does Not Exist on Operation

**Location:** API-Reference.md (lines 746-747)

**INCORRECT (documented):**
```swift
try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .attr(.userTier, "pro")
    .attr(.requestID, UUID().uuidString)
    .run { "response" }
```

**ACTUAL API:** The `Operation` type only has two public methods:
- `.capture(_: CapturePolicy)` - sets content capture policy
- `.run(_:)` or `.run(_: TraceHandle)` - executes the operation

The `Terra.attr()` method is `package static` and returns `Metadata`, not `Operation`. It cannot be chained.

**CORRECT:**
```swift
try await Terra
    .infer(Terra.ModelID("gpt-4o-mini"), prompt: prompt)
    .run { trace in
        trace.tag("app.user_tier", "pro")
        trace.tag("app.request_id", UUID().uuidString)
        return "response"
    }
```

---

### Issue #2: `.provider()` Method Does Not Exist on Operation

**Location:** API-Reference.md (line 248)

**INCORRECT (documented):**
```swift
try await Terra
    .agent("planner", id: "agent-42")
    .provider(Terra.ProviderID("openai"))
    .run { "agent response" }
```

**ACTUAL API:** The `provider` parameter is passed to the factory method, not chained on Operation.

**CORRECT:**
```swift
try await Terra
    .agent("planner", id: "agent-42", provider: Terra.ProviderID("openai"))
    .run { "agent response" }
```

---

### Issue #3: `.attr()` in Cookbook - Multiple Instances

**Location:** cookbook.md (lines 88, 102, 131, 141, 223, 224, 368)

**INCORRECT patterns:**
```swift
// Line 88
Terra.tool("web_search", callID: Terra.ToolCallID("search-1"))
    .attr(.init("search.query"), query)  // WRONG
    .run { trace in ... }

// Line 102
Terra.infer(Terra.ModelID("gpt-4o-mini"), ...)
    .attr(.init("step.name"), "summarize")  // WRONG
    .run { trace in ... }
```

**CORRECT pattern:**
```swift
Terra.tool("web_search", callID: Terra.ToolCallID("search-1"))
    .run { trace in
        trace.tag("search.query", query)
        // ...
    }
```

---

### Issue #4: `.attr()` in CoreML-Integration.md

**Location:** CoreML-Integration.md (lines 95-96, 123-124)

**INCORRECT:**
```swift
.mlModelConfiguration(.init(computeUnits: .all))
    .attr(.init("terra.coreml.compute_units"), "all")
    .attr(.init("terra.coreml.model_version"), "3.0")
```

**Issue:** This appears to be documenting a builder pattern for MLModelConfiguration, but the `.attr()` call is not valid Swift.

**CORRECT (if using Terra instrumentation):**
```swift
// Use Terra's MLModel instrumentation directly
// attributes are recorded via TraceHandle in the run closure
```

---

## Summary

| File | Issues | Severity |
|------|--------|----------|
| API-Reference.md | 2 (`.attr()`, `.provider()`) | CRITICAL |
| cookbook.md | 7 (`.attr()`) | CRITICAL |
| CoreML-Integration.md | 2 (`.attr()`) | HIGH |

**Total: 11 critical API inaccuracies**

## Fixes Required

1. **Remove** all `.attr()` chain calls from Operation examples in documentation
2. **Remove** all `.provider()` chain calls from Operation examples
3. **Replace** with correct `trace.tag()` usage inside run closures
4. **Update** examples to show provider being passed to factory methods directly
