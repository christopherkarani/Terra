package dev.terra.test

import dev.terra.*
import org.junit.Test
import org.junit.Assert.*
import org.junit.After
import org.junit.Before

/**
 * Integration tests for Terra Android SDK.
 *
 * These tests exercise the full Kotlin -> JNI -> Zig core pipeline.
 * They require libtera.so to be loaded, which means they must run on
 * an Android device or emulator (or a host with a compatible .so).
 *
 * On macOS/CI without an Android environment, these tests serve as
 * structural verification of the Kotlin API surface and will not execute.
 */
class TerraIntegrationTest {

    @Before
    fun setup() {
        Terra.initDefault()
    }

    @After
    fun teardown() {
        try { Terra.shutdown() } catch (_: Exception) {}
    }

    // ── Lifecycle ────────────────────────────────────────────────────────

    @Test
    fun `init and shutdown lifecycle`() {
        assertTrue("Should be running after init", Terra.isRunning)
        assertEquals(LifecycleState.RUNNING, Terra.lifecycleState)

        Terra.shutdown()

        assertFalse("Should not be running after shutdown", Terra.isRunning)
        assertEquals(LifecycleState.STOPPED, Terra.lifecycleState)
    }

    @Test(expected = IllegalStateException::class)
    fun `double init throws`() {
        // Already initialized in @Before
        Terra.initDefault()
    }

    @Test
    fun `shutdown is idempotent`() {
        Terra.shutdown()
        // Second shutdown should be a no-op (handle is already 0)
        Terra.shutdown()
        assertFalse(Terra.isRunning)
    }

    // ── Inference span full lifecycle ────────────────────────────────────

    @Test
    fun `inference span full lifecycle`() {
        val span = Terra.beginInferenceSpan("gpt-4")

        span.setAttribute("gen_ai.request.model", "gpt-4")
            .setAttribute("gen_ai.request.max_tokens", 2048L)
            .setAttribute("gen_ai.request.temperature", 0.7)
            .setAttribute("gen_ai.request.stream", false)
            .addEvent("prompt_sent")
            .setStatus(StatusCode.OK, "success")
            .end()
    }

    // ── All six span types ──────────────────────────────────────────────

    @Test
    fun `all six span types create and end`() {
        val inference = Terra.beginInferenceSpan("m")
        val embedding = Terra.beginEmbeddingSpan("m")
        val agent = Terra.beginAgentSpan("agent-1")
        val tool = Terra.beginToolSpan("search")
        val safety = Terra.beginSafetySpan("toxicity")
        val streaming = Terra.beginStreamingSpan("m")

        inference.end()
        embedding.end()
        agent.end()
        tool.end()
        safety.end()
        streaming.finish()
    }

    // ── Parent-child context propagation ────────────────────────────────

    @Test
    fun `parent child context propagation`() {
        val parent = Terra.beginInferenceSpan("parent")
        val ctx = parent.spanContext()

        assertTrue("trace_id should be valid", ctx.isValid)
        assertTrue("trace_id_hi or trace_id_lo should be non-zero",
            ctx.traceIdHi != 0L || ctx.traceIdLo != 0L)
        assertTrue("span_id should be non-zero", ctx.spanId != 0L)

        // Hex formatting should produce expected lengths
        assertEquals("traceIdHex should be 32 chars", 32, ctx.traceIdHex().length)
        assertEquals("spanIdHex should be 16 chars", 16, ctx.spanIdHex().length)

        val child = Terra.beginToolSpan("child-tool", parent = ctx)
        val childCtx = child.spanContext()

        // Child should share the same trace ID as the parent
        assertEquals("trace_id_hi should match parent", ctx.traceIdHi, childCtx.traceIdHi)
        assertEquals("trace_id_lo should match parent", ctx.traceIdLo, childCtx.traceIdLo)
        // Child should have a different span ID
        assertNotEquals("child span_id should differ from parent", ctx.spanId, childCtx.spanId)

        child.end()
        parent.end()
    }

    // ── Error recording ────────────────────────────────────────────────

    @Test
    fun `error recording sets status`() {
        val span = Terra.beginInferenceSpan("test")
        span.recordError("RuntimeError", "test error")
        span.end()
    }

    @Test
    fun `error recording without status change`() {
        val span = Terra.beginInferenceSpan("test")
        span.recordError("Warning", "non-fatal issue", setStatus = false)
        span.end()
    }

    // ── TerraSpan.use block ────────────────────────────────────────────

    @Test
    fun `use block auto-ends span`() {
        val span = Terra.beginInferenceSpan("auto-end")
        var blockExecuted = false

        span.use { s ->
            s.setAttribute("key", "value")
            blockExecuted = true
        }

        assertTrue("Block should have executed", blockExecuted)
    }

    @Test
    fun `use block records exception and rethrows`() {
        val span = Terra.beginInferenceSpan("error-test")
        try {
            span.use { _ ->
                throw RuntimeException("intentional error")
            }
            fail("Should have thrown")
        } catch (e: RuntimeException) {
            assertEquals("intentional error", e.message)
        }
    }

    @Test
    fun `use block returns value`() {
        val span = Terra.beginInferenceSpan("return-test")
        val result = span.use { s ->
            s.setAttribute("key", "value")
            42
        }
        assertEquals(42, result)
    }

    // ── Streaming span lifecycle ────────────────────────────────────────

    @Test
    fun `streaming span full lifecycle`() {
        val stream = Terra.beginStreamingSpan("stream-model")

        stream.recordFirstToken()
        stream.recordToken()
        stream.recordToken()
        stream.recordToken()

        assertEquals("Should have recorded 3 tokens", 3L, stream.tokenCount)

        stream.finish()
    }

    @Test
    fun `streaming scope use block auto-finishes`() {
        val stream = Terra.beginStreamingSpan("auto-finish")
        var tokensRecorded = 0L

        stream.use { scope ->
            scope.recordFirstToken()
            repeat(5) {
                scope.recordToken()
            }
            tokensRecorded = scope.tokenCount
        }

        assertEquals(5L, tokensRecorded)
    }

    @Test
    fun `streaming scope attributes and events`() {
        val stream = Terra.beginStreamingSpan("attr-test")

        stream.setAttribute("gen_ai.request.model", "gemma-2b")
            .setAttribute("gen_ai.request.max_tokens", 1024L)
            .setAttribute("gen_ai.request.temperature", 0.5)
            .setAttribute("gen_ai.request.stream", true)
            .addEvent("stream_started")

        stream.recordFirstToken()
        stream.recordToken()
        stream.finish()
    }

    @Test
    fun `streaming scope error recording`() {
        val stream = Terra.beginStreamingSpan("error-stream")
        stream.recordError("TimeoutError", "stream timed out")
        stream.finish()
    }

    @Test
    fun `streaming scope context extraction`() {
        val stream = Terra.beginStreamingSpan("ctx-stream")
        val ctx = stream.spanContext()
        assertTrue("Streaming span context should be valid", ctx.isValid)
        stream.finish()
    }

    // ── Service info and session ────────────────────────────────────────

    @Test
    fun `set service info`() {
        Terra.setServiceInfo("test-kotlin", "2.0.0")
    }

    @Test
    fun `set session id`() {
        Terra.setSessionId("kotlin-session-42")
    }

    // ── Diagnostics ────────────────────────────────────────────────────

    @Test
    fun `spans dropped initially zero`() {
        assertEquals(0L, Terra.spansDropped())
    }

    @Test
    fun `transport not degraded initially`() {
        assertFalse(Terra.transportDegraded())
    }

    @Test
    fun `version returns valid string`() {
        val version = Terra.version()
        assertNotNull(version)
        assertTrue("Version should match semver pattern",
            version.matches(Regex("""\d+\.\d+\.\d+""")))
    }

    @Test
    fun `last error code accessible`() {
        // Just verify it doesn't crash; value depends on state
        Terra.lastError()
    }

    // ── Metrics ────────────────────────────────────────────────────────

    @Test
    fun `record inference duration`() {
        Terra.recordInferenceDuration(150.5)
    }

    @Test
    fun `record token count`() {
        Terra.recordTokenCount(inputTokens = 128L, outputTokens = 256L)
    }

    // ── Attribute types ────────────────────────────────────────────────

    @Test
    fun `all attribute types on span`() {
        val span = Terra.beginInferenceSpan("attr-test")

        span.setAttribute("string.attr", "hello")
            .setAttribute("int.attr", 42L)
            .setAttribute("double.attr", 3.14)
            .setAttribute("bool.attr", true)

        span.end()
    }

    // ── Events ─────────────────────────────────────────────────────────

    @Test
    fun `events with and without timestamp`() {
        val span = Terra.beginInferenceSpan("event-test")

        span.addEvent("start")
        span.addEvent("checkpoint", System.nanoTime())
        span.addEvent("finish")

        span.end()
    }

    // ── Status codes ───────────────────────────────────────────────────

    @Test
    fun `all status codes`() {
        val unset = Terra.beginInferenceSpan("unset")
        unset.setStatus(StatusCode.UNSET)
        unset.end()

        val ok = Terra.beginInferenceSpan("ok")
        ok.setStatus(StatusCode.OK, "all good")
        ok.end()

        val error = Terra.beginInferenceSpan("error")
        error.setStatus(StatusCode.ERROR, "something failed")
        error.end()
    }

    // ── Fluent API chaining ────────────────────────────────────────────

    @Test
    fun `fluent chaining returns same span`() {
        val span = Terra.beginInferenceSpan("chain")
        val same = span
            .setAttribute("a", "b")
            .setAttribute("c", 1L)
            .setAttribute("d", 2.0)
            .setAttribute("e", false)
            .addEvent("event")
            .setStatus(StatusCode.OK)
            .recordError("type", "msg", setStatus = false)

        assertSame("Fluent methods should return the same span", span, same)
        span.end()
    }

    // ── Span ended guard ───────────────────────────────────────────────

    @Test(expected = IllegalStateException::class)
    fun `setAttribute on ended span throws`() {
        val span = Terra.beginInferenceSpan("ended")
        span.end()
        span.setAttribute("key", "value")
    }

    @Test(expected = IllegalStateException::class)
    fun `end on already ended span throws`() {
        val span = Terra.beginInferenceSpan("double-end")
        span.end()
        span.end()
    }

    @Test(expected = IllegalStateException::class)
    fun `spanContext on ended span throws`() {
        val span = Terra.beginInferenceSpan("ctx-ended")
        span.end()
        span.spanContext()
    }

    // ── StreamingScope finished guard ──────────────────────────────────

    @Test(expected = IllegalStateException::class)
    fun `recordToken on finished stream throws`() {
        val stream = Terra.beginStreamingSpan("finished")
        stream.finish()
        stream.recordToken()
    }

    @Test(expected = IllegalStateException::class)
    fun `double finish throws`() {
        val stream = Terra.beginStreamingSpan("double-finish")
        stream.finish()
        stream.finish()
    }

    // ── Config builder ─────────────────────────────────────────────────

    @Test
    fun `config builder defaults`() {
        Terra.shutdown() // tear down default init

        val config = TerraConfig.Builder()
            .maxSpans(2048)
            .batchSize(256)
            .contentPolicy(ContentPolicy.OPT_IN)
            .redactionStrategy(RedactionStrategy.LENGTH_ONLY)
            .serviceName("test-app")
            .serviceVersion("0.1.0")
            .otlpEndpoint("http://10.0.2.2:4318")
            .build()

        Terra.init(config)
        assertTrue(Terra.isRunning)
    }

    @Test
    fun `config DSL`() {
        Terra.shutdown()

        val config = terraConfig {
            maxSpans = 1024
            contentPolicy = ContentPolicy.ALWAYS
            serviceName = "dsl-test"
        }

        Terra.init(config)
        assertTrue(Terra.isRunning)
    }

    // ── TerraResource ──────────────────────────────────────────────────

    @Test
    fun `resource collection does not crash`() {
        val attrs = TerraResource.collect()
        assertNotNull(attrs)
        // On non-Android JVM, should return fallback attributes
        assertTrue("Should have os.type", attrs.containsKey("os.type"))
    }
}
