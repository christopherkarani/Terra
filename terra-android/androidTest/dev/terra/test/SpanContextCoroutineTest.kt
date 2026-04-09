package dev.terra.test

import dev.terra.*
import kotlinx.coroutines.*
import org.junit.Test
import org.junit.Assert.*
import org.junit.After

/**
 * Tests for SpanContext as a CoroutineContext.Element.
 *
 * Verifies that span context propagates correctly through Kotlin coroutine
 * structured concurrency, enabling parent-child span relationships across
 * suspend boundaries.
 *
 * Requires: kotlinx-coroutines-core, libtera.so loaded.
 * Must run on Android device/emulator.
 */
class SpanContextCoroutineTest {

    @After
    fun teardown() {
        try { Terra.shutdown() } catch (_: Exception) {}
    }

    @Test
    fun `SpanContext propagates through coroutine context`() = runBlocking {
        Terra.initDefault()

        val parent = Terra.beginInferenceSpan("parent")
        val ctx = parent.spanContext()

        withContext(ctx) {
            val current = coroutineContext[SpanContext]
            assertNotNull("SpanContext should be in coroutine context", current)
            assertEquals(ctx.traceIdHi, current!!.traceIdHi)
            assertEquals(ctx.traceIdLo, current.traceIdLo)
            assertEquals(ctx.spanId, current.spanId)
        }

        parent.end()
    }

    @Test
    fun `SpanContext survives coroutine dispatch`() = runBlocking {
        Terra.initDefault()

        val parent = Terra.beginInferenceSpan("dispatch-test")
        val ctx = parent.spanContext()

        val childCtx = withContext(Dispatchers.Default + ctx) {
            val propagated = coroutineContext[SpanContext]
            assertNotNull("Should propagate across dispatcher", propagated)

            // Create child span using propagated context
            val child = Terra.beginToolSpan("child-tool", parent = propagated)
            val childSpanCtx = child.spanContext()
            child.end()
            childSpanCtx
        }

        // Child should share trace ID with parent
        assertEquals(ctx.traceIdHi, childCtx.traceIdHi)
        assertEquals(ctx.traceIdLo, childCtx.traceIdLo)

        parent.end()
    }

    @Test
    fun `nested coroutine scopes maintain context`() = runBlocking {
        Terra.initDefault()

        val root = Terra.beginAgentSpan("agent")
        val rootCtx = root.spanContext()

        withContext(rootCtx) {
            val level1 = coroutineContext[SpanContext]
            assertNotNull(level1)

            // Create tool span as child
            val tool = Terra.beginToolSpan("tool-1", parent = level1)
            val toolCtx = tool.spanContext()

            withContext(toolCtx) {
                val level2 = coroutineContext[SpanContext]
                assertNotNull(level2)
                // Should be the tool's context now, not the root
                assertEquals(toolCtx.spanId, level2!!.spanId)
            }

            tool.end()
        }

        root.end()
    }

    @Test
    fun `SpanContext data class equality`() = runBlocking {
        Terra.initDefault()

        val span = Terra.beginInferenceSpan("equality-test")
        val ctx1 = span.spanContext()
        val ctx2 = SpanContext(ctx1.traceIdHi, ctx1.traceIdLo, ctx1.spanId)

        assertEquals("Data class should be equal by value", ctx1, ctx2)
        assertEquals("Hash codes should match", ctx1.hashCode(), ctx2.hashCode())

        span.end()
    }

    @Test
    fun `SpanContext isValid for zero context`() {
        val zero = SpanContext(0L, 0L, 0L)
        assertFalse("Zero context should not be valid", zero.isValid)

        val partial = SpanContext(0L, 1L, 0L)
        assertTrue("Non-zero trace ID should be valid", partial.isValid)
    }

    @Test
    fun `parallel coroutines with independent spans`() = runBlocking {
        Terra.initDefault()

        val parent = Terra.beginInferenceSpan("parallel-parent")
        val parentCtx = parent.spanContext()

        val results = withContext(parentCtx) {
            val deferred1 = async(Dispatchers.Default) {
                val ctx = coroutineContext[SpanContext]!!
                val span = Terra.beginToolSpan("tool-a", parent = ctx)
                val childCtx = span.spanContext()
                span.end()
                childCtx
            }

            val deferred2 = async(Dispatchers.Default) {
                val ctx = coroutineContext[SpanContext]!!
                val span = Terra.beginToolSpan("tool-b", parent = ctx)
                val childCtx = span.spanContext()
                span.end()
                childCtx
            }

            Pair(deferred1.await(), deferred2.await())
        }

        val (ctx1, ctx2) = results

        // Both children should share the same trace ID
        assertEquals(parentCtx.traceIdHi, ctx1.traceIdHi)
        assertEquals(parentCtx.traceIdHi, ctx2.traceIdHi)

        // But have different span IDs
        assertNotEquals("Parallel spans should have different IDs", ctx1.spanId, ctx2.spanId)

        parent.end()
    }
}
