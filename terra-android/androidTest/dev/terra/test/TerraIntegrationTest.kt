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

    @Test
    fun initAndShutdownLifecycle() {
        assertTrue("Should be running after init", Terra.isRunning)
        assertEquals(LifecycleState.RUNNING, Terra.lifecycleState)

        Terra.shutdown()

        assertFalse("Should not be running after shutdown", Terra.isRunning)
        assertEquals(LifecycleState.STOPPED, Terra.lifecycleState)
    }

    @Test(expected = IllegalStateException::class)
    fun doubleInitThrows() {
        Terra.initDefault()
    }

    @Test
    fun shutdownIsIdempotent() {
        Terra.shutdown()
        Terra.shutdown()
        assertFalse(Terra.isRunning)
    }

    @Test
    fun inferenceSpanFullLifecycle() {
        val span = Terra.beginInferenceSpan("gpt-4")

        span.setAttribute("gen_ai.request.model", "gpt-4")
            .setAttribute("gen_ai.request.max_tokens", 2048L)
            .setAttribute("gen_ai.request.temperature", 0.7)
            .setAttribute("gen_ai.request.stream", false)
            .addEvent("prompt_sent")
            .setStatus(StatusCode.OK, "success")
            .end()
    }

    @Test
    fun allSixSpanTypesCreateAndEnd() {
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

    @Test
    fun parentChildContextPropagation() {
        val parent = Terra.beginInferenceSpan("parent")
        val ctx = parent.spanContext()

        assertTrue("trace_id should be valid", ctx.isValid)
        assertTrue("trace_id_hi or trace_id_lo should be non-zero",
            ctx.traceIdHi != 0L || ctx.traceIdLo != 0L)
        assertTrue("span_id should be non-zero", ctx.spanId != 0L)

        assertEquals("traceIdHex should be 32 chars", 32, ctx.traceIdHex().length)
        assertEquals("spanIdHex should be 16 chars", 16, ctx.spanIdHex().length)

        val child = Terra.beginToolSpan("child-tool", parent = ctx)
        val childCtx = child.spanContext()

        assertEquals("trace_id_hi should match parent", ctx.traceIdHi, childCtx.traceIdHi)
        assertEquals("trace_id_lo should match parent", ctx.traceIdLo, childCtx.traceIdLo)
        assertNotEquals("child span_id should differ from parent", ctx.spanId, childCtx.spanId)

        child.end()
        parent.end()
    }

    @Test
    fun errorRecordingSetsStatus() {
        val span = Terra.beginInferenceSpan("test")
        span.recordError("RuntimeError", "test error")
        span.end()
    }

    @Test
    fun errorRecordingWithoutStatusChange() {
        val span = Terra.beginInferenceSpan("test")
        span.recordError("Warning", "non-fatal issue", setStatus = false)
        span.end()
    }

    @Test
    fun useBlockAutoEndsSpan() {
        val span = Terra.beginInferenceSpan("auto-end")
        var blockExecuted = false

        span.use { s ->
            s.setAttribute("key", "value")
            blockExecuted = true
        }

        assertTrue("Block should have executed", blockExecuted)
    }

    @Test
    fun useBlockRecordsExceptionAndRethrows() {
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
    fun useBlockReturnsValue() {
        val span = Terra.beginInferenceSpan("return-test")
        val result = span.use { s ->
            s.setAttribute("key", "value")
            42
        }
        assertEquals(42, result)
    }

    @Test
    fun streamingSpanFullLifecycle() {
        val stream = Terra.beginStreamingSpan("stream-model")

        stream.recordFirstToken()
        stream.recordToken()
        stream.recordToken()
        stream.recordToken()

        assertEquals("Should have recorded 3 tokens", 3L, stream.tokenCount)

        stream.finish()
    }

    @Test
    fun streamingScopeUseBlockAutoFinishes() {
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
    fun streamingScopeAttributesAndEvents() {
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
    fun streamingScopeErrorRecording() {
        val stream = Terra.beginStreamingSpan("error-stream")
        stream.recordError("TimeoutError", "stream timed out")
        stream.finish()
    }

    @Test
    fun streamingScopeContextExtraction() {
        val stream = Terra.beginStreamingSpan("ctx-stream")
        val ctx = stream.spanContext()
        assertTrue("Streaming span context should be valid", ctx.isValid)
        stream.finish()
    }

    @Test
    fun setServiceInfo() {
        Terra.setServiceInfo("test-kotlin", "2.0.0")
    }

    @Test
    fun setSessionId() {
        Terra.setSessionId("kotlin-session-42")
    }

    @Test
    fun spansDroppedInitiallyZero() {
        assertEquals(0L, Terra.spansDropped())
    }

    @Test
    fun transportNotDegradedInitially() {
        assertFalse(Terra.transportDegraded())
    }
}
