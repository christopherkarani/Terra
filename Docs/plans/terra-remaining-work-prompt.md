# Terra SDK — Complete Remaining Work (Phases 4–9)

> **For Claude Code:** This is a continuation prompt. Phases 0–3 of the API v3 implementation plan and Phases 2–3 of the 100% readiness plan are COMPLETE. This prompt covers ALL remaining work to bring the Terra SDK to release-candidate quality.

---

## Role

You are a senior Swift SDK engineer completing the Terra on-device GenAI observability SDK. Terra is built on OpenTelemetry and instruments model inference, embeddings, agent steps, tool calls, and safety checks across Apple platforms.

Your job is to execute Phases 4–9 of the 100% readiness plan using strict TDD (failing test → minimal implementation → commit). Every phase boundary must leave `swift test` green. You commit frequently, never skip tests, and never mark work complete without proving it works.

---

## Critical Context

### What's Already Done
- **Phase 2 (Configuration Consolidation):** `Terra.Configuration` is the single canonical config type. `AutoInstrumentConfiguration` and `StartProfile` are deprecated with compile-time guidance. 42 config tests pass.
- **Phase 3 (Lifecycle Hardening):** `Terra.LifecycleState` enum (`.uninitialized`/`.running`), `Terra.lifecycleState`, `Terra.isRunning`, `Terra.shutdown() async`. Full provider flush + teardown. 14 lifecycle tests (8 deterministic + 6 concurrency stress).
- **API v3 Implementation (Phases 0–10 of implementation plan):** Privacy enum (`PrivacyPolicy`), Trace protocol, closure-first factories (`Terra.inference {}`, `Terra.agent {}`, etc.), builder escape hatch (`.execute {}`), typed constants (`Terra.Key.*`), `TerraTraceable` protocol, task-local `AgentContext`, expanded `@Traced` macros (model/agent/tool/embedding/safety/streaming), Foundation Models session rewrite, examples + docs updated. 130+ tests green.

### What's Remaining (This Prompt)
Six phases, in order. Each has explicit exit criteria. Do not skip ahead.

### Branch and Working Directory
- Branch: `api-design` (based off `main`)
- Working directory: The Terra SPM package root
- Build: `swift build`
- Test: `swift test`
- Targeted test: `swift test --filter <TestTarget>.<TestClass>`

### Test Conventions
- Use `swift-testing` framework (`import Testing`, `@Test`, `#expect`) for all new tests
- Use `@Suite(.serialized)` for suites that touch the Terra singleton
- Use `lockTestingIsolation()`/`unlockTestingIsolation()` from `TerraTestSupport` in setUp/tearDown for any suite modifying global Terra state
- Port ranges for test servers: 14001–14099 (deterministic), 15001–15060 (concurrency)

### Commit Convention
- Commit after each sub-task passes tests
- Format: `<type>(<scope>): <description>` (e.g., `feat(privacy): gate exception messages on content policy`)
- Always include: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`

---

## Phase 4: Fluent + Closure API Finalization

### Goal
Make closure-first factories the primary API path. Builders become the documented "escape hatch" for dynamic metadata. Eliminate all internal usage of deprecated `.run {}` and `.capture(...)` outside of backward-compatibility tests.

### Tasks

#### 4.1: Audit and Eliminate Internal `.run {}` Usage
1. Search all `Sources/` files for `.run {` and `.run(` calls.
2. Replace every internal call site with `.execute {`.
3. Search `Tests/` files — keep `.run {}` ONLY in tests explicitly named `*Compatibility*` or `*Deprecated*` that verify the shim works. Convert all other test call sites to `.execute {}`.
4. Run `swift test` — all green.
5. Commit: `refactor(api): migrate all internal call sites from .run to .execute`

#### 4.2: Audit and Eliminate Internal `.capture(...)` Usage
1. Search all `Sources/` and `Tests/` for `.capture(` calls.
2. Replace with `.includeContent()` (except in explicit backward-compat tests).
3. Run `swift test` — all green.
4. Commit: `refactor(api): migrate .capture() to .includeContent()`

#### 4.3: API Parity Verification Tests
Write a test file `Tests/TerraTests/TerraAPIParityTests.swift` that proves behavioral equivalence between closure-first and builder-execute paths for ALL 6 span types:

```swift
@Suite(.serialized)
struct TerraAPIParityTests {
    // For each span type (inference, stream, agent, tool, embedding, safetyCheck):
    // 1. Call via closure-first: Terra.inference(model: "test") { "result" }
    // 2. Call via builder: Terra.inference(model: "test").execute { "result" }
    // 3. Assert both produce spans with identical:
    //    - span name
    //    - operation name attribute
    //    - model/name attributes
    //    - error recording behavior (throw inside both, verify same exception attributes)
}
```

Run `swift test --filter TerraTests.TerraAPIParityTests` — all green.
Commit: `test(api): add parity verification between closure-first and builder-execute paths`

### Exit Criteria
- `rg -n "\.run\s*\{" Sources/` returns zero matches (only deprecated shim definitions)
- `rg -n "\.run\s*\{" Tests/` returns matches ONLY in files with "Compat" or "Deprecated" in the name
- `TerraAPIParityTests` covers all 6 span types
- `swift test` green

---

## Phase 5: Macro Reliability Pass

### Goal
Harden the `@Traced` macro expansion against edge cases. Reduce auto-detection heuristic fragility. Ensure compile-time safety across all parameter shapes.

### Tasks

#### 5.1: Explicit-First Parameter Resolution
Modify `Sources/TerraTracedMacroPlugin/TracedMacro.swift`:

1. When a macro argument explicitly provides a value (e.g., `@Traced(model: "gpt-4", provider: "openai")`), that value MUST take absolute precedence over auto-detected function parameters.
2. Auto-detection should ONLY fill in values not provided by the macro arguments.
3. Add a clear comment in the code documenting the resolution order: `// Priority: 1. Explicit macro args  2. Auto-detected function params  3. Omitted (nil)`

#### 5.2: Comprehensive Macro Test Matrix
Add tests to `Tests/TerraTracedMacroTests/TracedMacroExpansionTests.swift` covering:

| Test Case | What It Validates |
|---|---|
| `@Traced(model:)` with no matching params | Expands with model only, no prompt/maxTokens |
| `@Traced(model:)` with `prompt: String` param | Auto-detects prompt |
| `@Traced(model:)` with `input: String` param | Auto-detects as prompt alias |
| `@Traced(model:)` with `query: String` param | Auto-detects as prompt alias |
| `@Traced(model:)` with `text: String` param | Auto-detects as prompt alias |
| `@Traced(model:)` with `message: String` param | Auto-detects as prompt alias |
| `@Traced(model:)` with `maxTokens: Int` param | Auto-detects maxOutputTokens |
| `@Traced(model:)` with `maxOutputTokens: Int` param | Auto-detects maxOutputTokens |
| `@Traced(model:)` with `temperature: Double` param | Auto-detects temperature |
| `@Traced(model:, streaming: true)` | Expands to `Terra.stream(...)` |
| `@Traced(agent:)` basic | Expands to `Terra.agent(name:)` |
| `@Traced(agent:, id:)` with explicit ID | Expands with provided ID |
| `@Traced(tool:)` basic | Expands to `Terra.tool(name:, callID: UUID().uuidString)` |
| `@Traced(tool:)` with `callID: String` param | Uses function param instead of UUID |
| `@Traced(embedding:)` basic | Expands to `Terra.embedding(model:)` |
| `@Traced(embedding:)` with `count: Int` param | Auto-detects inputCount |
| `@Traced(safety:)` basic | Expands to `Terra.safetyCheck(name:)` |
| `@Traced(safety:)` with `subject: String` param | Auto-detects subject |
| Function with no `async throws` | Produces a compile error (macro requires async) |
| Multiple matching params (e.g., `prompt: String, text: String`) | Uses first match, does not duplicate |
| Explicit macro arg overrides function param | `@Traced(model: "gpt-4")` on `func f(model: String)` — uses literal "gpt-4", not the function param |

#### 5.3: Import-Minimal Expansion Test
Add a test that verifies the macro expansion compiles with ONLY `import TerraCore` (or `import Terra`) — no implicit dependency on `OpenTelemetryApi` or other internal modules in the expanded code.

Commit after each sub-task: `test(macro): add comprehensive expansion test matrix`, `fix(macro): enforce explicit-first parameter resolution`

### Exit Criteria
- 20+ macro expansion tests covering all span types and parameter edge cases
- Explicit macro arguments always override auto-detected parameters
- `swift test --filter TerraTracedMacroTests` green
- `swift test` green

---

## Phase 6: Privacy & Security Completion

### Goal
Close all privacy audit findings. Ensure default-safe behavior across every call path. Add e2e redaction tests.

### Tasks

#### 6.1: Gate Exception Messages on Privacy Policy (Audit H-1)
**Problem:** `Scope.recordError(error)` attaches `exception.message` from `String(describing: error)` regardless of `contentPolicy`.

**Fix:**
1. Write failing test: With privacy = `.redacted`, throw an error whose description contains a sentinel string. Assert the exported span's exception event does NOT contain the sentinel in `exception.message`. It should contain only `exception.type`.
2. Modify `Sources/Terra/Terra+Scope.swift` (or wherever `recordError` is implemented):
   - Always record `exception.type` (the type name of the error).
   - Record `exception.message` ONLY when `shouldCapture` returns true for the current privacy policy.
   - When privacy forbids capture: omit `exception.message` entirely (do not hash it — error messages are not content the user opted into).
3. Run test — green.
4. Commit: `fix(privacy): gate exception.message recording on content policy`

#### 6.2: Keyed Hashing with HMAC-SHA256 (Audit H-2)
**Problem:** `terra.prompt.sha256` uses raw SHA-256, enabling cross-device correlation and dictionary attacks.

**Verify status:** This may already be partially addressed by the v3 `RedactionStrategy.hashHMACSHA256` default. Verify:
1. Check that `PrivacyPolicy.redacted` maps to `RedactionStrategy.hashHMACSHA256` (not `.hashSHA256`).
2. Check that an anonymization key is generated per-install if not explicitly provided.
3. Write test: Two different anonymization keys produce different hashes for the same input string.
4. Write test: The same key + same input produces the same hash (deterministic within install).
5. If raw SHA-256 paths still exist in any non-legacy code path, remove or gate behind `emitLegacySHA256Attributes`.
6. Commit: `fix(privacy): verify HMAC-SHA256 is default for all content hashing`

#### 6.3: Privacy Path Audit — Full Sweep
Systematically verify every call path that could emit user content:

| Call Path | File | What to Check |
|---|---|---|
| `Terra.inference(prompt:)` | `Terra+FluentAPI.swift` | Prompt only captured when `shouldCapture` is true |
| `Terra.safetyCheck(subject:)` | `Terra+FluentAPI.swift` | Subject only captured when `shouldCapture` is true |
| `.includeContent()` builder | `Terra+FluentAPI.swift` | Overrides policy only for that span, not globally |
| `Scope.recordError(error)` | `Terra+Scope.swift` | Gated per 6.1 |
| `@Traced` macro expansion | `TracedMacro.swift` | Expanded code passes through same privacy gates |
| HTTP auto-instrumentation | `HTTPAIInstrumentation.swift` | `url.full` not emitted (verify M-2 remediation holds) |
| CoreML swizzling | `CoreMLInstrumentation.swift` | No model input/output content captured |
| TerraFoundationModels | `TerraTracedSession.swift` | Transcript/tool args gated on privacy |
| Agent context accumulation | `Terra+AgentContext.swift` | Only tool/model NAMES accumulated (no content) |
| Streaming chunks | `StreamingTrace` | Chunk content not captured, only token counts |

For each path: read the code, verify the privacy gate, add a test if one doesn't exist.

Write test file: `Tests/TerraTests/TerraPrivacyAuditTests.swift` with one test per call path verifying default-safe behavior.

Commit: `test(privacy): add comprehensive privacy audit tests for all call paths`

#### 6.4: OpenClaw Default Host Fix (Audit M-1)
**Problem:** `Terra.start()` enables localhost OpenClaw gateway host monitoring even when `mode == .disabled`.

**Fix:**
1. In `Sources/TerraAutoInstrument/OpenClawConfiguration.swift` or `Terra+Start.swift`: when `OpenClawConfiguration.mode == .disabled`, set `gatewayHosts` to empty (do not merge default localhost hosts).
2. Write test: `Terra.Configuration()` with default OpenClaw mode produces no gateway hosts in the resulting instrumentation config.
3. Commit: `fix(config): disable OpenClaw gateway hosts when mode is disabled`

### Exit Criteria
- `TerraPrivacyAuditTests` covers all 10+ call paths from the table above
- Exception messages gated on privacy policy (H-1 closed)
- HMAC-SHA256 is the only hashing path for non-legacy code (H-2 closed)
- OpenClaw hosts empty when disabled (M-1 closed)
- `swift test` green

---

## Phase 7: Foundation Models & Wrapper Completion

### Goal
Complete the `TerraFoundationModels` integration with tool-call capture, guardrail spans, and generation option tracking. Align all wrapper modules (MLX, Llama, FoundationModels) on consistent metadata semantics.

### Tasks

#### 7.1: Tool-Call Capture via Transcript Diff
**Context:** After each `respond()` call in `TerraTracedSession`, diff the session transcript to discover internal tool calls made by the model.

1. Write failing test: Call `session.respond(to:)` where the mock backend simulates a tool call in the transcript. Assert the span contains events `tool_call` and `tool_result` with correct tool names.
2. Implement in `Sources/TerraFoundationModels/TerraTracedSession.swift`:
   - After each `respond()`, compare transcript before/after.
   - For each new tool call entry: emit `tool_call` event with tool name and (if privacy allows) arguments.
   - For each new tool result entry: emit `tool_result` event.
   - Record `terra.fm.tools.called` (array of tool names) and `terra.fm.tool_call_count` as span attributes.
3. Gate tool argument capture on privacy policy (tool names are always safe to record).
4. Commit: `feat(fm): add tool-call capture via transcript diff inspection`

> **Note:** Foundation Models APIs require macOS 26+. Use `#if canImport(FoundationModels)` guards. If you cannot run Foundation Models tests in the current environment, write the tests with appropriate availability guards and verify they compile.

#### 7.2: Guardrail Safety Spans
1. Write failing test: When the backend response indicates a guardrail violation, a child safety-check span is created.
2. Implement: When `respond()` throws a guardrail-related error or the response contains violation metadata, create a `Terra.safetyCheck(name: "foundation-model-guardrail")` child span with violation details.
3. Commit: `feat(fm): emit safety-check spans for guardrail violations`

#### 7.3: Generation Options Capture
1. Write test: When `GenerationOptions` are provided (temperature, sampling mode, max tokens), they appear as span attributes.
2. Implement: Extract generation options from the session configuration and record as attributes on inference spans.
3. Commit: `feat(fm): capture GenerationOptions as inference span attributes`

#### 7.4: Wrapper Consistency Audit
Review `TerraMLX`, `TerraLlama`, and `TerraFoundationModels` for consistent behavior:

| Behavior | MLX | Llama | FoundationModels |
|---|---|---|---|
| Error auto-recording | ✓ verify | ✓ verify | ✓ verify |
| Model name attribute | ✓ verify | ✓ verify | ✓ verify |
| Provider attribute | Should be "mlx" | Should be "llama.cpp" | Should be "apple/foundation-model" |
| Token usage recording | ✓ verify | ✓ verify | ✓ verify |
| Privacy gates | ✓ verify | ✓ verify | ✓ verify |
| Uses `.execute {}` (not `.run {}`) | ✓ verify | ✓ verify | ✓ verify |
| Streaming TTFT/TPS | if applicable | ✓ verify | ✓ verify |

Fix any inconsistencies found. Add a test to `Tests/TerraMLXTests/` if MLX wrapper is missing provider name.

Commit: `fix(wrappers): align MLX/Llama/FoundationModels on consistent metadata semantics`

### Exit Criteria
- Tool-call capture tested (transcript diff)
- Guardrail violations produce safety-check spans
- Generation options recorded as attributes
- All three wrapper modules have consistent provider names, error recording, and privacy gates
- `swift test` green

---

## Phase 8: Docs, Migration, and Developer UX

### Goal
A new developer can instrument their app in under 5 minutes using only the README. Legacy APIs are clearly documented as deprecated with migration paths.

### Tasks

#### 8.1: Rewrite README.md
Structure:
1. **Hero section:** 2-line pitch + 3-line hello world
2. **Quick Start:** `Terra.start()` + one `Terra.inference {}` example
3. **Setup presets:** quickstart / production / diagnostics table
4. **Span types:** table of 6 factory methods with 1-line examples each
5. **Privacy:** 4-case enum table with when-to-use guidance
6. **Macros:** `@Traced` examples for each span type
7. **Foundation Models:** `Terra.Session` drop-in example
8. **Builder API:** escape hatch section (for dynamic metadata)
9. **Advanced:** link to full docs, migration guide, API cookbook
10. **Installation:** SPM dependency snippet

Remove: all v1/v2 code examples from the main README body. Move to migration guide.

Commit: `docs: rewrite README for v3 canonical API`

#### 8.2: Migration Guide v1→v2→v3
Create `Docs/Migration_Guide.md`:

1. **v1→v3 mapping table:** `withInferenceSpan` → `Terra.inference {}`, etc.
2. **v2→v3 mapping table:** `.run {}` → `.execute {}`, `.capture(.optIn)` → `.includeContent()`
3. **Setup migration:** `Terra.enable(.quickstart)` → `Terra.start()`
4. **Privacy migration:** `ContentPolicy`/`CaptureIntent`/`RedactionStrategy` → `PrivacyPolicy` enum
5. **Deprecation timeline:** which APIs are deprecated, when they'll be removed
6. **Before/After code blocks** for each migration step

Commit: `docs: add comprehensive v1→v2→v3 migration guide`

#### 8.3: API Cookbook
Create `Docs/API_Cookbook.md` with copy-paste recipes:

1. **Basic inference:** instrument a single LLM call
2. **Streaming:** instrument a streaming response with TTFT
3. **Agent workflow:** agent span wrapping inference + tool calls
4. **Safety pipeline:** safety check → inference → post-check
5. **Foundation Models:** drop-in session replacement
6. **Custom metadata:** builder API with dynamic attributes
7. **Macro-based:** `@Traced` on functions and classes
8. **Privacy override:** per-call `.includeContent()` for debugging

Each recipe: 5–15 lines of code, with a comment explaining what telemetry it produces.

Commit: `docs: add API cookbook with 8 copy-paste recipes`

#### 8.4: Update CHANGELOG.md
Add a complete unreleased section covering all v3 changes:
- **Breaking:** list any breaking changes (with migration paths)
- **Added:** new APIs, macros, Foundation Models features
- **Changed:** renamed APIs, privacy simplification
- **Deprecated:** full list of deprecated APIs with recommended replacements
- **Fixed:** audit remediations (privacy, HMAC, OpenClaw)

Commit: `docs: update CHANGELOG with complete v3 unreleased section`

### Exit Criteria
- README leads with v3 API exclusively
- Migration guide covers v1→v3 and v2→v3 with before/after examples
- API cookbook has 8 working recipes
- CHANGELOG is complete and accurate
- A developer reading only the README can instrument their app in ≤ 5 minutes

---

## Phase 9: Release Qualification

### Goal
Validate the entire SDK is release-candidate quality. Zero known P1/P2 issues.

### Tasks

#### 9.1: Full Test Matrix
Run and verify ALL of these pass:

```bash
# Full test suite
swift test

# Targeted critical suites
swift test --filter TerraTests
swift test --filter TerraAutoInstrumentTests
swift test --filter TerraTracedMacroTests
swift test --filter TerraMLXTests
swift test --filter TerraTraceKitTests
swift test --filter TerraHTTPInstrumentTests

# Strict concurrency (warnings are OK for now, errors are not)
swift build -Xswiftc -strict-concurrency=complete 2>&1 | grep -c "error:"
# Expected: 0 errors
```

#### 9.2: Deprecation Sweep
Verify all deprecated APIs have:
1. `@available(*, deprecated, renamed: "newName")` or `@available(*, deprecated, message: "Use X instead")`
2. A forwarding implementation that delegates to the new API
3. At least one test proving the deprecated API still works (backward compat)

```bash
# List all deprecations
rg "@available.*deprecated" Sources/
```

#### 9.3: Internal Consistency Checks
```bash
# No internal usage of deprecated .run terminal (only shim definitions)
rg "\.run\s*\{" Sources/ --count
# Expected: only in deprecated shim definition files

# No raw SHA-256 in non-legacy paths
rg "sha256Hex" Sources/ --count
# Expected: only in legacy compatibility code with emitLegacySHA256Attributes guard

# All examples use v3 API
rg "withInferenceSpan\|withStreamingInferenceSpan\|withAgentInvocationSpan" Examples/
# Expected: 0 matches

# All examples use Terra.start()
rg "Terra\.enable\|Terra\.configure\|Terra\.install\|Terra\.bootstrap" Examples/
# Expected: 0 matches
```

#### 9.4: RC Checklist
Create `Docs/RC_CHECKLIST.md` and check off each item:

- [ ] `swift test` — all targets pass
- [ ] `swift build -Xswiftc -strict-concurrency=complete` — zero errors
- [ ] All 6 span types have: closure-first factory, builder escape hatch, macro support, parity test
- [ ] Privacy defaults are safe (`.redacted`, HMAC-SHA256, exception messages gated)
- [ ] All deprecated APIs have forwarding implementations and tests
- [ ] README uses only v3 API examples
- [ ] Migration guide covers v1→v3 and v2→v3
- [ ] CHANGELOG is complete
- [ ] Examples compile and demonstrate v3 patterns
- [ ] No P1/P2 issues in audit findings
- [ ] Lifecycle: start/shutdown/restart cycle tested under concurrency
- [ ] Foundation Models: tool capture, guardrails, generation options all tested
- [ ] Wrapper consistency: MLX, Llama, FoundationModels aligned

#### 9.5: Final Commit
After all checks pass:
```bash
git add Docs/RC_CHECKLIST.md
git commit -m "release: complete RC qualification checklist for v3"
```

### Exit Criteria
- `swift test` green across all targets
- `swift build -Xswiftc -strict-concurrency=complete` produces zero errors
- RC checklist fully checked off
- Zero known P1/P2 API or privacy issues
- Branch is ready for PR to `main`

---

## Definition of Done (100% Ready)

All of these must be true before this work is considered complete:

1. **Single canonical API path** — `Terra.start()` + `Terra.inference {}` is the only path shown to new users
2. **Legacy APIs deprecated** — all v1/v2 APIs have `@available(*, deprecated)` with forwarding impls
3. **Privacy default-safe** — `.redacted` policy, HMAC-SHA256 hashing, exception messages gated
4. **Full test coverage** — 150+ tests across all targets, including parity, privacy audit, macro matrix, and concurrency stress
5. **Docs aligned** — README, migration guide, cookbook, and changelog all reflect v3 API exclusively
6. **Wrappers consistent** — MLX, Llama, FoundationModels all follow the same metadata conventions
7. **RC checklist complete** — every item checked off with evidence

---

## Workflow Reminders

- **TDD always:** Write the failing test FIRST. Run it. See it fail. Then implement. Then see it pass. Then commit.
- **Commit frequently:** One commit per sub-task. Never batch multiple logical changes.
- **Test after every change:** `swift test` must be green before moving to the next task.
- **Read before editing:** Always read a file before modifying it. Understand existing code.
- **Minimal changes:** Only touch what's necessary. Don't refactor adjacent code.
- **No guessing:** If unclear about existing behavior, read the code and tests first.
- **Privacy first:** When in doubt, the privacy-safe path is correct.
