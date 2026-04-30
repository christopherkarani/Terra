# Terra Agent Source Map

Use this map when changing Terra so agents start from the canonical file instead
of chasing stale docs or incidental examples. Keep changes surgical and verify the
specific behavior listed for the task.

## Ground Rules

- Source of truth for public Swift APIs: `Sources/Terra`.
- Source of truth for telemetry key names: `Sources/Terra/Terra+Constants.swift`.
- Source of truth for viewer classification: `Sources/TerraTraceKit/TerraTelemetryClassifier.swift`.
- Source of truth for package targets and test target wiring: `Package.swift`.
- Do not treat historical audit docs as current API truth unless the doc says so.

## Common Task Map

| Task | Canonical files | Focus checks |
| --- | --- | --- |
| Add or rename a Terra telemetry key | `Sources/Terra/Terra+Constants.swift`, `Docs/telemetry-schema.json` | `python3 Scripts/validate-telemetry-schema.py` and the focused Swift tests that assert the key value |
| Update typed telemetry helpers | `Sources/Terra/Terra+KeyV3.swift`, `Sources/Terra/Terra+TypedTelemetryHelpers.swift`, `Sources/Terra/Terra+TraceProtocol.swift` | `swift test --filter TerraKeyV3Tests` and any helper-specific test |
| Change manual workflow, inference, stream, tool, or safety spans | `Sources/Terra/Terra+ManualTracing.swift`, `Sources/Terra/Terra.swift`, `Sources/Terra/Terra+FluentAPI.swift` | `swift test --filter TerraInferenceSpanTests`, `swift test --filter TerraStreamingSpanTests`, plus the affected workflow/tool tests |
| Change privacy or prompt capture behavior | `Sources/Terra/Terra+Privacy.swift`, `Sources/Terra/Terra+PrivacyV3.swift`, `Sources/Terra/TerraSpanEnrichmentProcessor.swift`, `Sources/Terra/Terra.swift` | `swift test --filter TerraPrivacyAuditTests` and `swift test --filter TerraRedactionPolicyTests` |
| Change HTTP AI auto-instrumentation | `Sources/TerraHTTPInstrument/HTTPAIInstrumentation.swift`, `Sources/TerraHTTPInstrument/HTTPAIStreamingObserver.swift`, `Sources/TerraHTTPInstrument/AIRequestParser.swift`, `Sources/TerraHTTPInstrument/AIResponseParser.swift`, `Sources/TerraHTTPInstrument/AIStreamingChunkParser.swift` | `swift test --filter TerraHTTPInstrumentTests` |
| Change Core ML instrumentation | `Sources/TerraCoreML/CoreMLInstrumentation.swift`, `Sources/TerraCoreML/TerraCoreML.swift`, `Sources/TerraCoreML/MLComputePlanDiagnostics.swift`, `Sources/TerraCoreML/ComputePlanAnalysis.swift` | `swift test --filter TerraCoreMLTests` |
| Change model stats or profiler attributes | `Sources/TerraAutoInstrument/ModelStatsSnapshot.swift`, `Sources/TerraSystemProfiler`, `Sources/TerraMetalProfiler`, `Sources/TerraPowerProfiler`, `Sources/TerraANEProfiler` | `swift test --filter TerraSystemProfilerTests`, `swift test --filter TerraPowerProfilerTests`, `swift test --filter TerraANEProfilerTests`, and any focused profiler test |
| Change execution route diagnostics | `Sources/Terra/Terra+ExecutionDiagnostics.swift`, `Sources/TerraCoreML/TerraCoreML.swift`, `Sources/TerraCoreML/ComputePlanAnalysis.swift` | `swift test --filter ComputePlanAnalysisTests` |
| Change OpenTelemetry installation/export behavior | `Sources/Terra/Terra+OpenTelemetry.swift`, `Sources/Terra/TerraSessionSpanProcessor.swift`, `Sources/TerraAutoInstrument/Terra+Lifecycle.swift`, `Sources/TerraAutoInstrument/Terra+Start.swift` | `swift test --filter TerraTests` plus exporter/session focused tests |
| Change trace loading, decoding, or local viewer behavior | `Sources/TerraTraceKit/OTLPDecoder.swift`, `Sources/TerraTraceKit/TraceLoader.swift`, `Sources/TerraTraceKit/TraceStore.swift`, `Sources/TerraTraceKit/TerraTelemetryClassifier.swift`, `Sources/TerraTraceKit/SpanDetailViewModel.swift`, `Sources/TerraTraceKit/TimelineViewModel.swift` | `swift test --filter TerraTraceKitTests` |
| Change macros or traced wrappers | `Sources/TerraTracedMacroPlugin/TracedMacro.swift`, `Sources/TerraTracedMacro/Traced.swift` | `swift test --filter TerraTracedMacroTests` |
| Update public docs or examples | `README.md`, `Docs/cookbook.md`, `Docs/integrations.md`, `Docs/migration.md`, `Sources/TerraAutoInstrument/Terra.docc`, `Examples` | `Scripts/validate_no_legacy_refs.sh` and any snippet-specific build/test |
| Validate package health after broad Swift changes | `Package.swift`, affected `Sources` and `Tests` targets | `Scripts/validate-swiftpm.sh` |

## Telemetry Schema Workflow

1. Add new stable or experimental keys to `Docs/telemetry-schema.json`.
2. Keep `key`, `type`, `unit`, `owner_module`, `stability`, `viewer_behavior`, and `examples` present on every registry item.
3. Prefer canonical `terra.*` or OpenTelemetry `gen_ai.*` keys over legacy aliases.
4. Mark legacy compatibility keys as `deprecated` and explain the replacement in `description`.
5. Run `python3 Scripts/validate-telemetry-schema.py` before handing off.

## Quick Search Recipes

| Need | Command |
| --- | --- |
| Find a telemetry key definition | `rg -n 'key_name|Keys\\.' Sources Tests Docs` |
| Find literal Terra or GenAI attributes | `rg -n '"(terra|gen_ai)\\.' Sources Tests Docs` |
| Find span names | `rg -n 'SpanNames|spanName|gen_ai\\.|terra\\.' Sources Tests` |
| Find viewer classifications | `rg -n 'TerraTelemetryClassifier|isHardwareEvent|isLifecycleEvent' Sources/TerraTraceKit Tests` |
