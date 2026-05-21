# Terra Public API Coverage

This is the current source-backed public API and documentation coverage matrix.
It is generated from source review of `Package.swift`, `Sources/**`,
`zig-core/**`, binding source trees, examples, and validation scripts. Historical
audit files are archival and are not authoritative.

## Swift Package Products

| Product / Target | Source of truth | Public surface | Canonical docs / examples | Validation |
| --- | --- | --- | --- | --- |
| `Terra` / `Terra` | `Sources/TerraAutoInstrument` | Umbrella module; re-exports `TerraCore`; `Terra.Configuration`, `ProductionIngest`, `Preset`, `Destination`, `Persistence`, `Profiling`, `ProfilerStatus`, `ProfilerDiagnostic`, `ProfilingDiagnostics`, `Features`; `Terra.start(_:)`, `quickStart()`, `profilingDiagnostics(for:)`, `lastProfilingDiagnostics`, `shutdown()`, `reset()`, `reconfigure(_:)`, `lifecycleState`, `isRunning` | `README.md`, `Docs/cookbook.md`, `Sources/TerraAutoInstrument/Terra.docc/Quickstart-90s.md`, `Configuration-Reference.md`, website | `TerraStartTests`, `TerraLifecycleAPITests`, `TerraConfigurationV3Tests`, `TerraQuickStartTests`, `DocumentationLintTests`, `CookbookSnippetsCompileTests` |
| `TerraCore` / `TerraCore` | `Sources/Terra` | `Terra`, `ProviderID`, `RuntimeID`, `ChatMessage`, `CapturePolicy`, `PrivacyPolicy`, `TerraError`, diagnostics/discovery helpers, workflow root APIs, `Operation`, `SpanHandle`, `ToolParentHandoff`, active-span hooks, visualization | `README.md`, `Docs/cookbook.md`, `Docs/integrations.md`, `Sources/TerraAutoInstrument/Terra.docc/Canonical-API.md`, `API-Reference.md`, `TerraCore.md`, `TerraError-Model.md`, `Typed-IDs.md` | `TerraComposableAPITests`, `TerraManualTracingTests`, `TerraStreamingSpanTests`, `TerraPrivacy*Tests`, `TerraDXTests`, snippet/lint tests |
| `TerraTraceKit` | `Sources/TerraTraceKit` | `TraceID`, `SpanID`, `SpanKind`, `StatusCode`, `AttributeValue`, `Attribute`, `Attributes`, `Resource`, `SpanEventRecord`, `SpanLinkRecord`, `SpanRecord`, `TraceFilter`, `TraceSnapshot`, `Trace`, `TraceDecoder`, `TraceFileLocator`, `TraceFileReader`, `TraceStore`, `OTLPRequestDecoder`, `OTLPHTTPServer`, renderers and view models | `Docs/telemetry-schema.json`, `Docs/BINDING_CONFORMANCE.md`, TraceKit references in DocC/API docs | `TerraTraceKitTests`, `TraceStoreTests`, `OTLPHTTPServerTests`, `OTLPRequestDecoderTests`, renderer/privacy tests, telemetry schema validator |
| `TerraHTTPInstrument` | `Sources/TerraHTTPInstrument` | `HTTPAIInstrumentation.defaultAIHosts`, `defaultOpenClawGatewayHosts`, `install(hosts:openClawGatewayHosts:openClawMode:)`; public parser/observer behavior is source-backed but most helpers are internal/package scoped | `Docs/integrations.md`, DocC configuration/API references | `TerraHTTPInstrumentTests`, `HTTPAIInstrumentationTests`, `HTTPAIInstrumentationSpanLinkageTests`, parser tests |
| `TerraFoundationModels` | `Sources/TerraFoundationModels` | `TerraTracedSession`, `Terra.TracedSession`; platform fallback exports `SystemLanguageModel`, `GenerationOptions`, `Generable`, `TerraFoundationModelsUnavailableError`; `respond(to:promptCapture:)`, structured `respond`, `streamResponse(to:promptCapture:)` | `Docs/integrations.md`, `Sources/TerraAutoInstrument/Terra.docc/FoundationModels.md` | `TerraTracedSessionTests` |
| `TerraMLX` | `Sources/TerraMLX` | `TerraMLX`, `Terra.MLX`, `StreamingTrace`, `traced(...)`, `tracedStream(...)`, `recordFirstToken()`, `recordTokenCount(_:)` | `Docs/integrations.md` | `TerraMLXTests` |
| `TerraCoreML` | `Sources/TerraCoreML` | `TerraCoreML.attributes(...)`, `CoreMLInstrumentation.Configuration/install`, `CalculatedMetrics`, `ComputeDeviceGuess`, `ModelSizeDetector`, macOS `EspressoLogCapture` and `EspressoLogSummary` | `Sources/TerraAutoInstrument/Terra.docc/CoreML-Integration.md`, `Configuration-Reference.md`, profiler docs | `TerraCoreMLTests`, `ComputePlanAnalysisTests`, `CalculatedMetricsTests`, `ModelSizeDetectorTests`, `EspressoLogParserTests` |
| `TerraMetalProfiler` | `Sources/TerraMetalProfiler` | `TerraMetalProfiler.install()`, `isInstalled`, `attributes(...)`, `estimatedCoreMLRouteAttributes(...)` | `Docs/Profiler-Integration.md`, DocC profiler/configuration docs | `TerraMetalProfilerAttributeTests` |
| `TerraSystemProfiler` | `Sources/TerraSystemProfiler` | `TerraSystemProfiler`, `MemorySnapshot`, `captureMemorySnapshot()`, `memoryDeltaAttributes(...)`, `ThermalMonitor`, `ThermalSample`, `MachTime`, `ThreadProfiler`, `NeuralEngineResearch`, `TelemetryAttributeConvertible` | `Docs/Profiler-Integration.md`, DocC profiler/configuration docs | `TerraSystemProfilerTests`, `ThermalMonitorTests`, `MachTimeTests` |
| `TerraAccelerate` | `Sources/TerraAccelerate` | `TerraAccelerate.Keys`, `TerraAccelerate.attributes(operation:durationMS:)` | This small helper is intentionally covered by this matrix and telemetry schema rather than a separate guide | Telemetry schema validation |
| `TerraPowerProfiler` | `Sources/TerraPowerProfiler` | macOS `PowerMetricsCollector`, `StartResult`, `PowerSample`, `PowerDomains`, `PowerSummary`, `PowerSummary.Status`; `startWithStatus`, `stop`, `stopIfActive` | `Docs/Profiler-Integration.md`, DocC profiler/configuration docs | `PowerMetricsCollectorTests`, `PowerMetricsParserTests`, `PowerSummaryTests` |
| `TerraANEProfiler` | `Sources/TerraANEProfiler` | `ANEHardwareProfiler`, `Mode`, `ANEProfilerSession`, `StartResult`, `ANEHardwareMetrics`; App-Store-safe default build does not enable private collection | `Docs/Profiler-Integration.md`, DocC profiler/configuration docs | `ANEHardwareMetricsTests` |
| `TerraTracedMacro` | `Sources/TerraTracedMacro`, `Sources/TerraTracedMacroPlugin` | `@Traced(model:...)`, `@Traced(agent:)`, `@Traced(tool:)`, `@Traced(embedding:)`, `@Traced(safety:)`; rejects `rethrows` and typed throws | `Sources/TerraAutoInstrument/Terra.docc/API-Reference.md` | `TerraTracedMacroTests`, `TracedMacroExpansionTests`, `TracedMacroPrivacyTests`, import smoke tests |

## Canonical Swift Usage

Use `Terra.workflow(name:id:_:)` for one user request or agent turn. Put
`infer`, `stream`, `embed`, `tool`, `safety`, and `agent` child work under the
workflow handle. Use `workflow(..., messages:)` when Terra owns transcript
mutation. Use `Terra.startSpan(name:id:attributes:)` only when manual lifecycle
control is required.

`SpanHandle` is the current public handle. Child inference, stream, tool,
embedding, safety, and agent handles are closure-scoped. For deferred tool work
discovered inside an inference or stream child, capture `span.handoff()` or use
`span.withToolParent(...)` while a live workflow/manual parent still exists.

Privacy is additive. `.capture(.includeContent)` opts an operation into
content-derived telemetry, but the active `Terra.PrivacyPolicy` still decides
whether content is dropped, length-only, or hashed. `PrivacyPolicy.capturing`
uses HMAC hashing for content-derived attributes; it is not raw-content export.

`Terra.Configuration.Profiling.extended` is `[.memory, .thermal, .metal]` and
`.all` is `[.memory, .thermal, .metal, .espresso]`. `.power` and `.ane` are
reserved flags in the umbrella configuration; import and run
`TerraPowerProfiler` or `TerraANEProfiler` directly when those opt-in modules are
needed.

## Native And Binding Surfaces

| Surface | Source of truth | Public surface | Docs / examples | Validation |
| --- | --- | --- | --- | --- |
| C ABI | `Sources/CTerraBridge/include/terra.h`, `zig-core/include/terra.h`, vendored xcframework header | Opaque handles, lifecycle/content/redaction/status enums, `terra_config_t`, vtables, robotics transports, lifecycle/config/span/events/error/stream/context/diagnostics/version/metrics/test APIs | `Docs/BINDING_CONFORMANCE.md`, `Docs/PLATFORM-COMPATIBILITY.md`, `Docs/ROBOTICS-PILOT.md`, binding READMEs | `Scripts/validate-bindings.py --matrix`, header byte parity, vendored symbol checks |
| Zig core | `zig-core/src`, `zig-core/include/terra.h`, `zig-core/cli` | Stable C ABI exports; public Zig modules for core embedding; CLI commands `doctor`, `validate`, `listen`, `trace`; `zig build bench` for benchmarks | `Docs/BINDING_CONFORMANCE.md`, this matrix, source CLI help | Zig tests through `Scripts/validate.sh --quick`; binding validator for stable ABI |
| Rust | `terra-rust/src` | `Terra`, `TerraConfig`, `TerraSpan`, `SpanContext`, `Version`, enums, lifecycle/config/span/metrics/diagnostic/closure helpers | `terra-rust/README.md`, `terra-rust/examples/basic.rs`, `Docs/BINDING_CONFORMANCE.md` | Rust tests and binding matrix |
| Python | `terra-python/terra.py` | `Terra`, `TerraConfig`, `TerraSpan`, `TerraStreamingSpan`, `SpanContext`, enums, lifecycle/span/stream/diagnostic/metrics methods | Module API plus tests; covered in binding matrix | Python compile/unit tests and binding matrix |
| Android/Kotlin | `terra-android/kotlin`, `terra-android/jni` | `Terra`, `TerraConfig`, `terraConfig`, `ProductionIngest`, `TerraSpan`, `StreamingScope`, `SpanContext`, transports, `TerraResource` | `terra-android/README.md`, JVM contract tests, binding matrix | JVM tests when Java is installed; Android Gradle outside quick mode |
| C++ | `terra-cpp/include/terra.hpp` | RAII `Instance`, `Span`, `StreamingSpan`, `SpanContext`, enums, `Error` | `terra-cpp/examples/basic.cpp` | C++ smoke validation through `Scripts/validate.sh` |
| ROS2 pilot | `terra-ros2` | `terra_ros2_node`, `/terra/traces`, `/terra/metrics`, node parameters for endpoint, robot/vehicle/mission/component/autonomy/privacy/redaction | `terra-ros2/README.md`, `Docs/ROBOTICS-PILOT.md` | `Scripts/validate-ros2-package.sh`; full runtime validation requires `colcon` and a collector |
| User scripts | `Scripts` | `validate.sh`, `validate-doc-snippets.py`, `validate_no_legacy_refs.sh`, `validate-bindings.py`, `validate-telemetry-schema.py`, `validate-swiftpm.sh`, `validate-ros2-package.sh`, native build/publish helpers | `Docs/BINDING_CONFORMANCE.md`, `Docs/ROBOTICS-PILOT.md`, `Docs/PLATFORM-COMPATIBILITY.md`, final task notes | Script validation plus `validate.sh --quick` |

## Intentional Exclusions

| Surface | Reason |
| --- | --- |
| `TerraLlama` | Package target exists, but it is not a Swift Package product and its client-facing API is package scoped. It should not be taught as a public import surface. |
| `TerraTracedMacroPlugin` | Compiler plugin implementation detail. Public API is the `TerraTracedMacro` macro declarations. |
| `CTerraBridge`, `CTerraANEBridge`, `libtera` SwiftPM targets | Bridge implementation targets. Public user-facing native API is the C header and the documented language bindings. |
| Historical audit and plan docs | Archival only. They are retained for context and marked as non-authoritative. |

## Drift Guards

- `Scripts/validate-doc-snippets.py` scans README, cookbook, integrations,
  DocC pages, examples, and website source for removed front-facing API names
  and DocC link drift.
- `Scripts/validate_no_legacy_refs.sh` scans canonical docs, DocC, examples,
  and website source for legacy public API teaching.
- `DocumentationLintTests` duplicates the high-value canonical API lint inside
  Swift tests.
- `CookbookSnippetsCompileTests` compile-checks README/cookbook recipes and the
  website recipe snippet against the live public Swift API.
- `Scripts/validate-bindings.py --matrix` checks C/Zig/Rust/Python/Kotlin/C++
  constants, feature presence, header parity, vendored symbols, and golden trace
  privacy shape.
- `Scripts/validate-telemetry-schema.py` checks the telemetry schema and Swift
  source key registration.

Remaining known limits: binding validation is token/source-shape validation, not
a complete ABI layout diff; DocC/integrations snippets are linted but not all
compile-mirrored; Android and ROS2 runtime validation require Java/Android and
ROS2/`colcon` environments respectively.
