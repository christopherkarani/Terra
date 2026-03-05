# Front-Facing API Rating Report (After)

Date: 2026-03-05  
Scope: `Terra` + `TerraCore` + `TerraTracedMacro` (front-facing consumer API)

## Overall Score

**87/100 — Release Ready**

## Gate Status (hard gates)

- Human DX: **4.6/5** (pass)
- Agent DX: **4.6/5** (pass)
- Power & Extensibility: **4.6/5** (pass)
- Naming Quality: **4.8/5** (pass)
- Concurrency Safety & Compliance: **4.6/5** (pass)

## Category Breakdown (weighted)

- Human DX: 17/18
- Agent DX: 17/18
- Naming Quality: 13/14
- Surface Efficiency: 6/8
- Power & Extensibility: 16/17
- Swift 6.2 Composition Elegance: 9/10
- Concurrency Safety & Compliance: 9/10
- Error + Migration Quality: 5/5
- Penalties: -5

## Top Findings (post-redesign)

1. **Canonical API is now coherent and predictable**
   - Unified call entrypoints (`infer/stream/embed/agent/tool/safety`) and typed IDs reduce ambiguity for humans and agents.
2. **Error model and lifecycle semantics are stable**
   - Public `TerraError` mapping and actor-serialized lifecycle make failure handling deterministic.
3. **Surface efficiency remains the main gap**
   - Added public seam abstractions improve extensibility but increased the public symbol count in `TerraCore`.

## Targeted Follow-Ups

1. Prune low-value seam overloads and helper symbols in `Terra+ComposableAPI` to recover surface-efficiency points.
2. Continue consolidating overload clusters that differ only by optional context inputs.
3. Keep macro expansion tests pinned to canonical signatures to prevent future API drift.
