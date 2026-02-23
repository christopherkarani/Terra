# Terra Android — Technical Plan

Date: 2026-02-23
Author: Chris Karani
Status: Draft

---

## 1. Mission

Build `terra-android`, a Kotlin-first on-device GenAI observability SDK for Android that implements the `terra.v1` telemetry convention. The SDK must produce OTLP spans that are schema-compatible with Terra Swift — meaning an Android app and an iOS app instrumented with their respective SDKs emit structurally identical traces viewable in the same TraceMacApp instance.

### Success Criteria

1. All spans emitted by `terra-android` pass `terra.v1` contract validation (same 6 required attributes, same runtime allowlist, same span names).
2. TraceMacApp displays Android-originated traces with zero viewer changes.
3. Privacy model parity: `ContentPolicy`, `RedactionStrategy`, `AnonymizationPolicy` behave identically.
4. At least 4 runtimes instrumented at launch: TFLite, HTTP AI APIs (OkHttp), llama.cpp (JNI), and MediaPipe LLM Inference.
5. Streaming telemetry (TTFT, TPS, stall detection) works for HTTP SSE/NDJSON and llama.cpp token callbacks.
6. Published to Maven Central with API level 26+ (Android 8.0) minimum.

---

## 2. Repository Strategy

### Repo Layout

| Repository | Purpose |
|---|---|
| `terra-spec` (new) | Telemetry convention docs, JSON schema, contract conformance test fixtures, protobuf definitions. Shared by both SDKs. |
| `terra` (existing, rename to `terra-swift`) | Apple SDK — unchanged except spec files move to `terra-spec`. |
| `terra-android` (new) | Android/Kotlin SDK — this plan. |

### Why Separate Repos

- Zero shared application code between Swift and Kotlin SDKs.
- Different build systems (SPM/Xcode vs Gradle/AGP), CI pipelines (GitHub Actions macOS vs Linux/Android emulator), and release cadences.
- The shared artifact is the `terra.v1` spec — a document/schema repo, not a code repo.
- Contributors rarely touch both platforms. Monorepo would add friction without benefit.

### terra-spec Extraction (Prerequisite)

Extract from `terra-swift`:
- `Docs/TelemetryConvention/terra-v1.md`
- `Docs/TelemetryConvention/terra-v1.schema.json`
- `Docs/TelemetryConvention/GOVERNANCE.md`
- Contract conformance test fixtures (`Tests/TerraTraceKitTests/Fixtures/TerraV1/`)

Both SDKs reference `terra-spec` as a git submodule or CI dependency for contract conformance testing.

---

## 3. Architecture

### Module Dependency Graph

```
terra-android (umbrella)
├── terra-core          → OTel wiring, public API, privacy, schema enforcement
├── terra-tflite        → TFLite Interpreter instrumentation
├── terra-http          → OkHttp interceptor for cloud AI APIs
├── terra-mediapipe     → MediaPipe LLM Inference / ML Kit wrapping
├── terra-llama         → llama.cpp JNI bridge (reuses C header)
├── terra-onnx          → ONNX Runtime instrumentation (Phase 2)
├── terra-system        → Memory, thermal, thread profiling
└── terra-gpu           → GPU delegate detection, Vulkan queries (Phase 2)
```

Published as individual Gradle modules. Developers include only what they use:

```kotlin
// build.gradle.kts
dependencies {
    implementation("dev.terra:terra-core:1.0.0")
    implementation("dev.terra:terra-tflite:1.0.0")
    implementation("dev.terra:terra-http:1.0.0")
}
```

### Mapping to Terra Swift

| Terra Swift Module | Terra Android Module | Instrumentation Strategy |
|---|---|---|
| `Terra` (Sources/Terra/) | `terra-core` | Direct port — same API shape in Kotlin |
| `TerraAutoInstrument` | `terra-android` umbrella | Gradle plugin for auto-wiring (Phase 2) |
| `TerraCoreML` | `terra-tflite` | Wrapper pattern (user passes Interpreter calls through Terra) |
| `TerraHTTPInstrument` | `terra-http` | OkHttp Interceptor (cleaner than URLSession callbacks) |
| `TerraFoundationModels` | `terra-mediapipe` | MediaPipe LLM Inference API wrapping |
| `TerraMLX` | N/A | No Android equivalent |
| `TerraLlama` | `terra-llama` | Same C header, JNI bindings instead of @_cdecl |
| `TerraAccelerate` | N/A | No Android equivalent (vDSP is Apple-only) |
| `TerraSystemProfiler` | `terra-system` | /proc/self/status, PowerManager, ActivityManager |
| `TerraMetalProfiler` | `terra-gpu` | Vulkan queries, GPU delegate detection |

---

## 4. Core SDK Design (`terra-core`)

### 4.1 Public API

Mirror Terra Swift's API shape for cross-platform familiarity:

```kotlin
// One-time setup
Terra.install(context) {
    privacy {
        contentPolicy = ContentPolicy.NEVER          // default: never capture content
        redactionStrategy = RedactionStrategy.SHA256  // default: hash
        anonymization {
            enabled = true
            keyRotationInterval = 24.hours
        }
    }
    compliance {
        exportControl { allowedRegions = listOf("US", "EU") }
        retention { maxAge = 7.days; maxSize = 50.megabytes }
    }
    telemetry {
        tokenLifecyclePolicy {
            sampleEveryN = 1
            maxEventsPerSpan = 500
        }
    }
    export {
        otlpEndpoint = "http://localhost:4318"
    }
}

// Inference span
val result = Terra.withInferenceSpan(
    request = InferenceRequest(
        model = ModelFingerprint("model=gemma-2b|runtime=tflite|quant=int8"),
        prompt = "Summarize this article",
        maxTokens = 256
    )
) { scope ->
    // User's inference code here
    val output = interpreter.run(inputBuffer, outputBuffer)
    scope.setOutputTokenCount(output.tokenCount)
    output
}

// Streaming inference
Terra.withStreamingInferenceSpan(request) { scope ->
    llamaSession.generate(prompt) { token ->
        scope.recordToken(token)  // TTFT, TPS, stall detection
    }
}
```

### 4.2 Constants (direct port from Terra+Constants.swift)

```kotlin
object SpanNames {
    const val MODEL_LOAD = "terra.model.load"
    const val INFERENCE = "terra.inference"
    const val STAGE_PROMPT_EVAL = "terra.stage.prompt_eval"
    const val STAGE_DECODE = "terra.stage.decode"
    const val STREAM_LIFECYCLE = "terra.stream.lifecycle"
}

object Keys {
    const val SEMANTIC_VERSION = "terra.semantic.version"
    const val SCHEMA_FAMILY = "terra.schema.family"
    const val RUNTIME = "terra.runtime"
    const val REQUEST_ID = "terra.request.id"
    const val SESSION_ID = "terra.session.id"
    const val MODEL_FINGERPRINT = "terra.model.fingerprint"
    // ... 80+ keys, identical to Swift
}

enum class RuntimeKind(val value: String) {
    TFLITE("tflite"),
    MEDIAPIPE("mediapipe"),
    ONNX_RUNTIME("onnx_runtime"),
    OLLAMA("ollama"),
    LM_STUDIO("lm_studio"),
    LLAMA_CPP("llama_cpp"),
    HTTP_API("http_api"),
    EXECUTORCH("executorch");
}
```

> **Schema evolution note:** Android introduces new runtime values (`tflite`, `mediapipe`, `onnx_runtime`, `executorch`). These require a `terra.v1.1` minor version bump in `terra-spec`. The schema JSON's `allowed_runtime_values` array gains these entries. Existing viewers ignore unknown runtimes gracefully (they already handle the `unknown` fallback path in `TerraTelemetryClassifier`).

### 4.3 OpenTelemetry Integration

```kotlin
// OTel Android SDK is mature — less wiring needed than Swift
dependencies {
    implementation("io.opentelemetry.android:android-sdk:0.6.0")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp:1.40.0")
    implementation("io.opentelemetry:opentelemetry-sdk:1.40.0")
}
```

- Use `OpenTelemetrySdk.builder()` with OTLP/HTTP exporter targeting `localhost:4318` (same as Swift).
- `TerraSessionSpanProcessor` equivalent: inject `session.id` and `session.previousId` on all spans.
- `TerraSpanEnrichmentProcessor` equivalent: inject privacy metadata, schema version.
- Batch export with configurable interval (default 5s, matching Swift).

### 4.4 Privacy Model (direct port)

```kotlin
enum class ContentPolicy { NEVER, OPT_IN, ALWAYS }

enum class RedactionStrategy { DROP, LENGTH_ONLY, SHA256 }

data class AnonymizationPolicy(
    val enabled: Boolean = true,
    val keyRotationInterval: Duration = 24.hours,
    val algorithm: String = "HmacSHA256"
)

data class CompliancePolicy(
    val exportControl: ExportControl = ExportControl(),
    val retention: RetentionPolicy = RetentionPolicy(),
    val auditEvents: Boolean = true
)
```

Defaults identical to Swift: `ContentPolicy.NEVER`, `RedactionStrategy.SHA256`, 24h key rotation. HMAC via `javax.crypto.Mac` (no external dependency needed).

### 4.5 Scope Wrappers (type-safe spans)

```kotlin
// Sealed interface markers (equivalent to Swift's empty enum Kind markers)
sealed interface SpanKind {
    data object Inference : SpanKind
    data object ModelLoad : SpanKind
    data object StreamLifecycle : SpanKind
    data object Embedding : SpanKind
    data object AgentInvocation : SpanKind
    data object ToolExecution : SpanKind
    data object SafetyCheck : SpanKind
}

class Scope<T : SpanKind> internal constructor(
    private val span: Span
) {
    fun addEvent(name: String, attributes: Attributes = Attributes.empty()) { ... }
    fun setAttributes(vararg pairs: Pair<String, Any>) { ... }
    fun recordError(error: Throwable) { ... }
    val span: Span get() = span  // escape hatch
}
```

### 4.6 Streaming Inference Scope

```kotlin
class StreamingInferenceScope internal constructor(
    span: Span,
    private val clock: Clock = Clock.monotonic(),
    private val policy: TokenLifecyclePolicy
) : Scope<SpanKind.Inference>(span) {

    private val startTime = clock.now()
    private var firstTokenTime: Instant? = null
    private var tokenCount = 0
    private var lastTokenTime: Instant? = null
    private val stallThresholdMs = 300L

    fun recordToken(token: String? = null) {
        val now = clock.now()
        tokenCount++

        if (firstTokenTime == null) {
            firstTokenTime = now
            val ttft = (now - startTime).inWholeMilliseconds
            addEvent("terra.first_token", attributesOf(
                Keys.STREAM_TTFT_MS to ttft.toDouble()
            ))
        }

        // Stall detection
        lastTokenTime?.let { last ->
            val gap = (now - last).inWholeMilliseconds
            if (gap > stallThresholdMs) {
                addEvent("terra.anomaly.stalled_token", attributesOf(
                    Keys.TOKEN_GAP_MS to gap.toDouble(),
                    Keys.STALL_THRESHOLD_MS to stallThresholdMs.toDouble()
                ))
            }
        }

        // Token lifecycle event (respects sampling policy)
        if (tokenCount % policy.sampleEveryN == 0 && tokenCount <= policy.maxEventsPerSpan) {
            addEvent("terra.token.lifecycle", attributesOf(
                Keys.TOKEN_INDEX to tokenCount.toLong(),
                Keys.TOKEN_GAP_MS to lastTokenTime?.let { (now - it).inWholeMilliseconds.toDouble() } ?: 0.0,
                Keys.TOKEN_STAGE to "decode"
            ))
        }

        lastTokenTime = now
    }

    internal fun finish() {
        val duration = (clock.now() - startTime).inWholeMilliseconds
        val tps = if (duration > 0) tokenCount * 1000.0 / duration else 0.0
        setAttributes(
            Keys.STREAM_OUTPUT_TOKENS to tokenCount.toLong(),
            Keys.STREAM_TPS to tps,
            Keys.LATENCY_E2E_MS to duration.toDouble()
        )
        firstTokenTime?.let {
            setAttributes(Keys.STREAM_TTFT_MS to (it - startTime).inWholeMilliseconds.toDouble())
        }
    }
}
```

---

## 5. Instrumentation Modules

### 5.1 terra-tflite (Phase 1)

**Strategy:** Wrapper pattern. User passes their TFLite operations through Terra.

```kotlin
// Usage
val result = TerraTFLite.traced(
    model = ModelFingerprint("model=mobilenet-v2|runtime=tflite|quant=int8"),
    interpreter = interpreter
) { tracedInterpreter ->
    tracedInterpreter.run(inputBuffer, outputBuffer)
}

// Internal: wraps Interpreter with span lifecycle
class TracedInterpreter(
    private val interpreter: Interpreter,
    private val scope: Scope<SpanKind.Inference>
) {
    fun run(input: ByteBuffer, output: ByteBuffer) {
        scope.setAttributes(
            "terra.tflite.delegate" to detectDelegate(interpreter),
            "terra.tflite.num_threads" to interpreter.getOptions().numThreads
        )
        val result = interpreter.run(input, output)
        scope.setAttributes(
            "terra.tflite.inference_time_ms" to interpreter.getLastNativeInferenceDurationNanoseconds() / 1_000_000.0
        )
        return result
    }
}
```

**What it captures:**
- Model load duration
- Inference duration (from TFLite's native timer)
- Delegate type (CPU, GPU, NNAPI, Hexagon)
- Thread count
- Input/output tensor shapes
- Memory delta (via `/proc/self/status` VmRSS before/after)

**Why not bytecode instrumentation:** AGP Transform API is fragile across TFLite versions, adds build complexity, and breaks ProGuard. The wrapper is explicit, zero-magic, and matches TerraMLX's pattern.

### 5.2 terra-http (Phase 1)

**Strategy:** OkHttp Interceptor. Automatic for all OkHttp-based HTTP clients.

```kotlin
// Setup
val client = OkHttpClient.Builder()
    .addInterceptor(TerraAIInterceptor())
    .build()

// Or auto-install for all OkHttp instances (via OkHttp EventListener.Factory)
Terra.install(context) {
    http { autoInstrument = true }
}
```

**What it captures:**
- Provider detection: OpenAI, Anthropic, Google AI, Cohere, Mistral, Groq, Together, Fireworks, Ollama, LM Studio
- Request parsing: model name, max_tokens, temperature, stream flag
- Response parsing: model name (from response), token counts (prompt + completion)
- Streaming: SSE and NDJSON parsing (port of `AIResponseStreamParser` from Swift)
  - TTFT, TPS, chunk count, stall detection at 300ms gaps
- Runtime classification heuristic (same confidence scoring as Swift, 0.2-1.0)
- Max 10 MiB body parsing cap

**Implementation detail:** OkHttp's `Interceptor` interface is significantly cleaner than URLSession instrumentation. A single `intercept(chain: Chain): Response` method gives access to both request and response with full body streaming.

```kotlin
class TerraAIInterceptor : Interceptor {
    override fun intercept(chain: Chain): Response {
        val request = chain.request()
        val provider = ProviderDetector.detect(request.url)
            ?: return chain.proceed(request)  // Not an AI API — pass through

        return Terra.withInferenceSpan(
            request = parseInferenceRequest(request, provider)
        ) { scope ->
            val response = chain.proceed(request)
            if (isStreaming(response)) {
                parseStreamingResponse(response, scope)
            } else {
                parseResponse(response, scope)
            }
            response
        }
    }
}
```

### 5.3 terra-llama (Phase 1)

**Strategy:** JNI bridge to the same C callback header used by Terra Swift.

```
terra-llama/
├── src/main/kotlin/dev/terra/llama/
│   ├── TerraLlama.kt              # Public API
│   └── LlamaCallbackBridge.kt     # JNI ↔ Kotlin bridge
├── src/main/cpp/
│   ├── TerraLlamaHooks.h          # SHARED with terra-swift (identical header)
│   ├── terra_llama_jni.cpp         # JNI native methods
│   └── CMakeLists.txt
└── build.gradle.kts
```

**Shared C header** (`TerraLlamaHooks.h` — identical to Swift repo):

```c
void terra_llama_record_token_event(int handle, int index, double gap_ms, double logprob);
void terra_llama_record_stage_event(int handle, const char* stage, double duration_ms, int token_count);
void terra_llama_record_stall_event(int handle, double gap_ms, double threshold_ms);
void terra_llama_finish_stream(int handle, int total_tokens, double total_duration_ms);
```

**JNI bridge:**

```kotlin
// Kotlin side
object LlamaCallbackBridge {
    private val lock = ReentrantLock()
    private val activeScopes = ConcurrentHashMap<Int, StreamingInferenceScope>()

    fun register(handle: Int, scope: StreamingInferenceScope) {
        activeScopes[handle] = scope
    }

    fun unregister(handle: Int) {
        activeScopes.remove(handle)
    }

    // Called from JNI
    @JvmStatic
    fun onTokenEvent(handle: Int, index: Int, gapMs: Double, logprob: Double) {
        activeScopes[handle]?.recordToken()
    }

    // Called from JNI
    @JvmStatic
    fun onStageEvent(handle: Int, stage: String, durationMs: Double, tokenCount: Int) {
        activeScopes[handle]?.addEvent("terra.stage.$stage", attributesOf(
            Keys.STAGE_NAME to stage,
            Keys.STAGE_TOKEN_COUNT to tokenCount.toLong(),
            "terra.stage.duration_ms" to durationMs
        ))
    }
}
```

### 5.4 terra-mediapipe (Phase 1)

**Strategy:** Wrapper around MediaPipe's LLM Inference API.

```kotlin
val result = TerraMediaPipe.traced(
    model = ModelFingerprint("model=gemma-2b|runtime=mediapipe|quant=int8"),
    session = llmInference
) { tracedSession ->
    tracedSession.generateResponse(prompt)
}

// Streaming
TerraMediaPipe.tracedStream(model, session) { tracedSession ->
    tracedSession.generateResponseAsync(prompt).collect { partialResult ->
        // User processes partial results
        // Terra automatically tracks TTFT, TPS, stalls
    }
}
```

**What it captures:**
- Model load time
- Inference latency
- Token counts (from MediaPipe's response metadata)
- Streaming metrics (TTFT, TPS) via Flow collection interception
- Backend delegate (CPU/GPU)
- Memory delta

### 5.5 terra-system (Phase 1)

**Strategy:** Platform APIs + procfs.

```kotlin
object TerraSystemProfiler {

    // Memory via /proc/self/status
    fun memorySnapshot(): MemorySnapshot {
        val status = File("/proc/self/status").readText()
        val vmRss = parseVmRss(status)   // VmRSS line in kB
        val vmPeak = parseVmPeak(status)  // VmPeak line in kB
        return MemorySnapshot(
            residentMb = vmRss / 1024.0,
            peakMb = vmPeak / 1024.0,
            nativeHeapMb = Debug.getNativeHeapAllocatedSize() / (1024.0 * 1024.0)
        )
    }

    // Thermal state (API 29+)
    fun thermalState(context: Context): String {
        val pm = context.getSystemService(PowerManager::class.java)
        return when (pm.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE -> "nominal"
            PowerManager.THERMAL_STATUS_LIGHT -> "fair"
            PowerManager.THERMAL_STATUS_MODERATE -> "serious"
            PowerManager.THERMAL_STATUS_SEVERE -> "critical"
            PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
            PowerManager.THERMAL_STATUS_EMERGENCY -> "critical"
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
            else -> "unknown"
        }
    }

    // Thread count via /proc/self/task
    fun threadCount(): Int {
        return File("/proc/self/task").listFiles()?.size ?: -1
    }

    // Battery / power state
    fun powerState(context: Context): String {
        val bm = context.getSystemService(BatteryManager::class.java)
        val charging = bm.isCharging
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (charging) "charging" else "battery_$level"
    }
}
```

Mapped to `terra.v1` hardware attributes:

| terra.v1 Attribute | Android Source |
|---|---|
| `terra.process.thermal_state` | `PowerManager.currentThermalStatus` |
| `terra.hw.power_state` | `BatteryManager.isCharging` + capacity |
| `terra.hw.memory_pressure` | `ActivityManager.getMemoryInfo().lowMemory` |
| `terra.process.memory_resident_delta_mb` | `/proc/self/status` VmRSS delta |
| `terra.process.memory_peak_mb` | `/proc/self/status` VmPeak |
| `terra.hw.rss_mb` | `/proc/self/status` VmRSS |
| `terra.hw.gpu_occupancy_pct` | Phase 2 — Vulkan/vendor-specific |
| `terra.hw.ane_utilization_pct` | N/A on Android (Apple-specific) |

### 5.6 terra-gpu (Phase 2)

Deferred. Android GPU profiling is fragmented across Adreno/Mali/PowerVR. Phase 2 will target:
- GPU delegate detection (is NNAPI/GPU delegate active?)
- Vulkan timestamp queries for GPU compute time
- Vendor sysfs nodes for GPU frequency/utilization (best-effort)

### 5.7 terra-onnx (Phase 2)

ONNX Runtime on Android. Similar wrapper pattern to TFLite:

```kotlin
val result = TerraOnnxRuntime.traced(model, session) { tracedSession ->
    tracedSession.run(inputs)
}
```

---

## 6. terra-spec: Schema Evolution

### 6.1 New Runtime Values

`terra.v1.1` adds Android-specific runtime values:

```json
{
    "terra.runtime": {
        "enum": [
            "coreml", "foundation_models", "mlx",
            "ollama", "lm_studio", "llama_cpp",
            "openclaw_gateway", "http_api",
            "tflite", "mediapipe", "onnx_runtime", "executorch"
        ]
    }
}
```

This is a **backward-compatible minor version** — existing viewers handle unknown runtimes via the `unknown` fallback path. TraceMacApp's `TraceRuntime.swift` needs a color mapping update for new runtimes.

### 6.2 New Hardware Attributes (Android-specific)

```json
{
    "terra.hw.nnapi_accelerator": { "type": "string" },
    "terra.hw.gpu_delegate_active": { "type": "boolean" },
    "terra.hw.soc_model": { "type": "string" }
}
```

Added as optional attributes — no contract breakage.

### 6.3 Contract Conformance Tests

Both SDKs run the same conformance suite against shared fixtures:

```
terra-spec/
├── terra-v1.md
├── terra-v1.schema.json
├── GOVERNANCE.md
├── fixtures/
│   ├── valid/
│   │   ├── inference-coreml.json
│   │   ├── inference-tflite.json       # NEW
│   │   ├── inference-mediapipe.json    # NEW
│   │   ├── streaming-ollama.json
│   │   ├── streaming-llamacpp.json
│   │   └── ...
│   └── invalid/
│       ├── missing-runtime.json
│       ├── unknown-version.json
│       └── ...
└── conformance/
    ├── swift/    # Swift test harness
    └── kotlin/   # Kotlin test harness
```

---

## 7. Build System

### 7.1 Project Structure

```
terra-android/
├── terra-core/
│   ├── src/main/kotlin/dev/terra/core/
│   ├── src/test/kotlin/dev/terra/core/
│   └── build.gradle.kts
├── terra-tflite/
│   ├── src/main/kotlin/dev/terra/tflite/
│   ├── src/test/kotlin/dev/terra/tflite/
│   └── build.gradle.kts
├── terra-http/
│   ├── src/main/kotlin/dev/terra/http/
│   ├── src/test/kotlin/dev/terra/http/
│   └── build.gradle.kts
├── terra-mediapipe/
│   └── ...
├── terra-llama/
│   ├── src/main/kotlin/dev/terra/llama/
│   ├── src/main/cpp/
│   └── build.gradle.kts
├── terra-system/
│   └── ...
├── sample/
│   ├── src/main/kotlin/dev/terra/sample/
│   └── build.gradle.kts
├── settings.gradle.kts
├── build.gradle.kts
├── gradle.properties
└── CLAUDE.md
```

### 7.2 Gradle Configuration

```kotlin
// settings.gradle.kts
rootProject.name = "terra-android"

include(
    ":terra-core",
    ":terra-tflite",
    ":terra-http",
    ":terra-mediapipe",
    ":terra-llama",
    ":terra-system",
    ":sample"
)
```

```kotlin
// terra-core/build.gradle.kts
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    namespace = "dev.terra.core"
    compileSdk = 35
    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
}

dependencies {
    implementation("io.opentelemetry:opentelemetry-api:1.40.0")
    implementation("io.opentelemetry:opentelemetry-sdk:1.40.0")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp:1.40.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("io.opentelemetry:opentelemetry-sdk-testing:1.40.0")
}
```

### 7.3 CI (GitHub Actions)

```yaml
name: terra-android CI

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true  # for terra-spec

      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Build all modules
        run: ./gradlew build

      - name: Unit tests
        run: ./gradlew test

      - name: Contract conformance
        run: ./gradlew :terra-core:testConformance

      - name: Lint
        run: ./gradlew detekt

  instrumented-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 30
          script: ./gradlew connectedAndroidTest
```

---

## 8. External Dependencies

| Package | Version | Purpose |
|---|---|---|
| `io.opentelemetry:opentelemetry-api` | 1.40.0+ | OTel API |
| `io.opentelemetry:opentelemetry-sdk` | 1.40.0+ | OTel SDK |
| `io.opentelemetry:opentelemetry-exporter-otlp` | 1.40.0+ | OTLP/HTTP export |
| `io.opentelemetry:opentelemetry-sdk-testing` | 1.40.0+ | Test utilities (InMemorySpanExporter) |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core` | 1.8.1+ | Coroutines |
| `com.squareup.okhttp3:okhttp` | 4.12.0+ | HTTP interceptor (compileOnly) |
| `org.tensorflow:tensorflow-lite` | 2.16.0+ | TFLite instrumentation (compileOnly) |
| `com.google.mediapipe:tasks-genai` | 0.10.14+ | MediaPipe LLM (compileOnly) |

Runtime-specific dependencies (`okhttp`, `tensorflow-lite`, `mediapipe`) are `compileOnly` — they are **not** transitive. Users bring their own versions.

---

## 9. Testing Strategy

### 9.1 Test Levels

| Level | Framework | What it tests |
|---|---|---|
| Unit tests | JUnit 5 + kotlin-test | Core logic, parsing, privacy, schema enforcement |
| Contract conformance | JUnit 5 + shared fixtures | terra.v1 schema compliance against terra-spec fixtures |
| Integration tests | Android instrumented tests | OTel wiring, OTLP export, system profiler on real device |
| Interceptor tests | MockWebServer (OkHttp) | HTTP parsing, provider detection, streaming SSE/NDJSON |
| JNI tests | JUnit 5 + native test | llama.cpp callback bridge round-trip |

### 9.2 InMemorySpanExporter

Same pattern as Terra Swift's `InMemoryExporter`:

```kotlin
class TerraTestHarness {
    private val spanExporter = InMemorySpanExporter.create()

    fun install(): Terra {
        Terra.install(testContext) {
            export { exporter = spanExporter }
        }
        return Terra
    }

    fun exportedSpans(): List<SpanData> = spanExporter.finishedSpanItems

    fun assertSpanExists(name: String, block: (SpanData) -> Unit = {}) {
        val span = exportedSpans().find { it.name == name }
            ?: fail("No span with name '$name' found. Have: ${exportedSpans().map { it.name }}")
        block(span)
    }

    fun reset() = spanExporter.reset()
}
```

### 9.3 Contract Conformance Suite

```kotlin
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class TerraV1ConformanceTest {

    @ParameterizedTest
    @MethodSource("validFixtures")
    fun `valid fixtures pass contract validation`(fixture: File) {
        val spans = OTLPDecoder.decode(fixture.readBytes())
        assertTrue(spans.isNotEmpty(), "Fixture ${fixture.name} produced no spans")
        spans.forEach { span ->
            assertContainsRequiredAttributes(span)
            assertValidRuntime(span)
            assertSchemaVersion(span, "v1")
        }
    }

    @ParameterizedTest
    @MethodSource("invalidFixtures")
    fun `invalid fixtures are rejected`(fixture: File) {
        assertThrows<SchemaValidationException> {
            OTLPDecoder.decode(fixture.readBytes())
        }
    }

    companion object {
        @JvmStatic
        fun validFixtures() = File("terra-spec/fixtures/valid").listFiles()!!.toList()

        @JvmStatic
        fun invalidFixtures() = File("terra-spec/fixtures/invalid").listFiles()!!.toList()
    }
}
```

---

## 10. Phased Delivery

### Phase 1: MVP (Weeks 1-8)

| Week | Deliverable |
|---|---|
| 1-2 | `terra-core`: Public API, OTel wiring, privacy model, constants, scope wrappers |
| 3 | `terra-core`: Streaming inference scope, token lifecycle, stall detection |
| 4 | `terra-system`: Memory, thermal, thread profiling |
| 5 | `terra-http`: OkHttp interceptor, provider detection, SSE/NDJSON streaming parser |
| 6 | `terra-tflite`: TFLite wrapper, delegate detection, memory delta |
| 7 | `terra-llama`: JNI bridge, C header integration, streaming callbacks |
| 8 | Integration testing, contract conformance, sample app, Maven Central publish |

**MVP ships:** Core SDK + OkHttp interceptor + TFLite wrapper + llama.cpp JNI + system profiler. OTLP export to existing TraceMacApp.

### Phase 2: Full Parity (Weeks 9-16)

| Week | Deliverable |
|---|---|
| 9-10 | `terra-mediapipe`: MediaPipe LLM Inference wrapping, Flow-based streaming |
| 11 | `terra-onnx`: ONNX Runtime wrapper |
| 12 | `terra-gpu`: GPU delegate detection, Vulkan queries (best-effort) |
| 13-14 | Gradle plugin for auto-instrumentation (auto-wires interceptors) |
| 15 | Performance benchmarks, ProGuard rules, R8 compatibility |
| 16 | Documentation, migration guides, public release |

### Phase 3: Advanced (Weeks 17+)

- Executorch instrumentation (Meta's on-device inference runtime)
- Qualcomm QNN SDK instrumentation
- Samsung ONE (On-Device Neural Engine) instrumentation
- Android-native trace viewer (Jetpack Compose)
- Recommendations engine (port of `TerraRecommendationEngine`)
- Anomaly detection (thermal correlation, model regression)

---

## 11. Open Questions

| # | Question | Impact | Proposed Answer |
|---|---|---|---|
| 1 | Should `terra-spec` be a git submodule or published artifact? | Build complexity vs. version pinning | Git submodule — simpler, both SDKs always test against same spec revision |
| 2 | Should we support Kotlin Multiplatform (KMP) for shared logic? | Future desktop/server support | No for v1 — Android-first. KMP adds complexity without clear benefit yet |
| 3 | Min API level 26 vs 21? | Device coverage (~95% vs ~99%) | API 26 — thermal APIs need 29+, and 26+ covers ~98% of active devices |
| 4 | Should `terra-http` support Ktor/Fuel/Retrofit in addition to OkHttp? | Developer reach | OkHttp-only for v1 — Retrofit uses OkHttp under the hood, Ktor is niche on Android |
| 5 | Maven group ID: `dev.terra` or `io.github.christopherkarani.terra`? | Publishing identity | `dev.terra` if domain owned, otherwise `io.github.christopherkarani.terra` |
| 6 | Auto-instrumentation via Gradle plugin (AGP Transform) or manual? | DX vs. build complexity | Manual for v1, Gradle plugin in Phase 2 |
| 7 | Should TraceMacApp add Android runtime colors, or defer to a separate viewer? | Viewer UX | Add runtime colors to TraceMacApp — small change, big payoff |

---

## 12. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| TFLite API changes break instrumentation | Medium | Medium | compileOnly dependency + version matrix CI testing |
| Android GPU profiling too fragmented to be useful | High | Low | Ship without GPU metrics in v1; add best-effort in Phase 2 |
| OTel Android SDK missing features vs. Swift SDK | Low | Medium | OTel Android is mature; fallback to manual span management |
| JNI bridge crashes on certain ABIs | Low | High | Test on arm64-v8a, armeabi-v7a, x86_64 in CI emulator matrix |
| MediaPipe LLM Inference API changes rapidly | Medium | Medium | Pin to stable version, compileOnly dependency |
| Schema evolution breaks cross-platform compat | Low | Critical | Contract conformance tests in CI for both SDKs against shared fixtures |
| ProGuard/R8 strips OTel reflection | Medium | Medium | Ship ProGuard rules in each module's consumer rules |

---

## 13. Non-Goals (Explicit)

1. **No Kotlin Multiplatform** in v1. Android-only.
2. **No auto-instrumentation via bytecode** in v1. Wrapper pattern only.
3. **No Android trace viewer** in v1. Use existing TraceMacApp over network.
4. **No server-side collection** changes. Same OTLP/HTTP on port 4318.
5. **No backward compatibility** with pre-v1 schemas. terra.v1 only.
6. **No iOS code changes** except adding Android runtime colors to TraceMacApp.
