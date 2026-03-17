# Terra Android SDK

On-device GenAI observability for Android, powered by Terra's Zig core engine.

## Architecture

```
Kotlin SDK (dev.terra.*)
    ↓ JNI
terra_jni.c
    ↓ C ABI
libtera.so (Zig cross-compiled)
```

The Zig core handles span lifecycle, ring buffer management, batching, privacy/redaction, and OTLP protobuf serialization. The Kotlin layer provides an idiomatic Android API with coroutine context propagation.

## Building

### Prerequisites

- Zig 0.14+ (for cross-compilation)
- Android SDK with API 26+ (for Kotlin SDK)
- Kotlin 1.9+

### Cross-compile libtera for Android

```bash
cd zig-core/

# ARM64 (most Android devices)
zig build -Dtarget=aarch64-linux-android -Doptimize=ReleaseSafe

# x86_64 (emulators)
zig build -Dtarget=x86_64-linux-android -Doptimize=ReleaseSafe
```

### Place native libraries

Copy the built `.so` files into the Gradle-expected layout:

```bash
mkdir -p terra-android/jniLibs/arm64-v8a
mkdir -p terra-android/jniLibs/x86_64

cp zig-core/zig-out/lib/libterra.so terra-android/jniLibs/arm64-v8a/
# (repeat for x86_64 target)
```

### Build the AAR

```bash
cd terra-android/
./gradlew assembleRelease
```

## Usage

### Initialization

```kotlin
import dev.terra.*

// Default configuration
Terra.init()

// Custom configuration with Kotlin DSL
Terra.init(terraConfig {
    serviceName = "my-android-app"
    serviceVersion = "2.1.0"
    maxSpans = 8192
    contentPolicy = ContentPolicy.OPT_IN
    otlpEndpoint = "https://otel-collector.example.com:4318"
})
```

### Inference Spans

```kotlin
val span = Terra.beginInferenceSpan("gemma-2b")
span.use { s ->
    s.setAttribute("gen_ai.request.max_tokens", 256L)

    val result = runInference(prompt)

    s.setAttribute("gen_ai.response.model", result.model)
    s.setAttribute("gen_ai.usage.output_tokens", result.tokenCount.toLong())
    s.setStatus(StatusCode.OK)
}
```

### Streaming with Token Tracking

```kotlin
val stream = Terra.beginStreamingSpan("gemma-2b")
stream.use { scope ->
    var first = true
    for (token in model.stream(prompt)) {
        if (first) {
            scope.recordFirstToken()
            first = false
        }
        scope.recordToken()
        emit(token)
    }
}
// Automatically records: TTFT, token count, tokens/sec
```

### Context Propagation with Coroutines

```kotlin
val agentSpan = Terra.beginAgentSpan("search-agent")
val agentCtx = agentSpan.spanContext()

// Pass context through coroutines
withContext(agentCtx) {
    val parentCtx = coroutineContext[SpanContext]
    val toolSpan = Terra.beginToolSpan("web-search", parent = parentCtx)
    toolSpan.use { s ->
        // This span is a child of the agent span
        val results = webSearch(query)
        s.setAttribute("terra.tool.result_count", results.size.toLong())
    }
}
agentSpan.end()
```

### Error Recording

```kotlin
val span = Terra.beginInferenceSpan("gemma-2b")
try {
    val result = runInference(prompt)
    span.setStatus(StatusCode.OK)
} catch (e: Exception) {
    span.recordError(e.javaClass.name, e.message ?: "Unknown error")
} finally {
    span.end()
}
```

### Shutdown

```kotlin
// In Application.onTerminate() or lifecycle callback
Terra.shutdown()
```

## Device Resource Attributes

Call `TerraResource.collect()` to get device metadata following OTel semantic conventions:

```kotlin
val attrs = TerraResource.collect()
// device.model.identifier → "Pixel 8"
// device.manufacturer → "Google"
// os.version → "14"
// host.arch → "arm64-v8a"
// terra.android.sdk_int → "34"
```

## Privacy

Terra enforces privacy at the engine level:

| Policy | Behavior |
|--------|----------|
| `ContentPolicy.NEVER` (default) | Prompt/response content is never captured |
| `ContentPolicy.OPT_IN` | Content captured only when `includeContent = true` per span |
| `ContentPolicy.ALWAYS` | All content captured |

Redaction strategies (`RedactionStrategy.HMAC_SHA256` default) hash sensitive content before export.

## API Reference

### Terra (singleton)

| Method | Description |
|--------|-------------|
| `init(config)` | Initialize with configuration |
| `shutdown()` | Flush and tear down |
| `isRunning` | Check if running |
| `beginInferenceSpan(model)` | Start inference span |
| `beginEmbeddingSpan(model)` | Start embedding span |
| `beginAgentSpan(name)` | Start agent span |
| `beginToolSpan(name)` | Start tool span |
| `beginSafetySpan(name)` | Start safety check span |
| `beginStreamingSpan(model)` | Start streaming span |
| `recordInferenceDuration(ms)` | Record duration metric |
| `recordTokenCount(in, out)` | Record token metrics |
| `spansDropped()` | Ring buffer overflow count |
| `version()` | Library version string |

### TerraSpan

| Method | Description |
|--------|-------------|
| `setAttribute(key, value)` | Set string/long/double/bool attribute |
| `setStatus(code, desc?)` | Set span status |
| `addEvent(name)` | Add event at current time |
| `recordError(type, msg)` | Record error event |
| `spanContext()` | Extract trace/span IDs |
| `end()` | End the span |
| `use { }` | Scoped block with auto-end |

### StreamingScope

| Method | Description |
|--------|-------------|
| `recordToken()` | Record a token |
| `recordFirstToken()` | Record TTFT |
| `finish()` | End streaming span |
| `use { }` | Scoped block with auto-finish |
