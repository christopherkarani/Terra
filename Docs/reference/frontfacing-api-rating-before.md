# Front-Facing API Rating Report (Before)

Date: 2026-03-05  
Scope: `Terra` + `TerraCore` + `TerraTracedMacro` (front-facing consumer API)

## Overall Score

**63/100 — Not Release Ready** (this is the “before” baseline for the vNext clean-break work).

## Gate Status (hard gates)

- Human DX: **3.6/5** (fail)
- Agent DX: **3.4/5** (fail)
- Power & Extensibility: **4.2/5** (fail)
- Naming Quality: **3.8/5** (fail)
- Concurrency Safety & Compliance: **3.6/5** (fail)

## Category Breakdown (weighted)

- Human DX: 13/18
- Agent DX: 12/18
- Naming Quality: 11/14
- Surface Efficiency: 6/8
- Power & Extensibility: 14/17
- Swift 6.2 Composition Elegance: 6/10
- Concurrency Safety & Compliance: 7/10
- Error + Migration Quality: 2/5
- Penalties: -8

## Top Findings (baseline issues)

1. **Lifecycle is not a stable public contract**
   - `shutdown`/`isRunning`/`lifecycleState` are `package`, and `start` stickiness is enforced via internal error types.
2. **Capture model duplication**
   - `CapturePolicy` and `CaptureIntent` represent the same “per-call capture override” concept with different names.
3. **`OperationKind` abstraction boundary is broken**
   - It’s public but empty and unusable for consumers (no public conformers); it adds generics without value.
4. **Stringly typed identifiers**
   - model/provider/runtime/call IDs are all `String`, which increases misuse and reduces autocomplete guidance.
5. **Macro expansion relies on `package` APIs**
   - `@Traced` expands to `.execute` and `Terra.inference(...)`-style calls, which are not guaranteed usable outside the package.

## Targeted Fixes (expected score gains)

1. Public lifecycle actor + deterministic semantics (+12)
2. Typed IDs + unified capture (+8)
3. Remove `OperationKind`, make `Call` non-generic (+5)
4. Stable `TerraError` (+4)
5. Executor/runtime seams + metadata builder + macro canonicalization (+10)

