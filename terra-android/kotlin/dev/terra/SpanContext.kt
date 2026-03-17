package dev.terra

import kotlin.coroutines.CoroutineContext

/**
 * SpanContext — Carries trace/span IDs for parent-child propagation.
 *
 * Maps to terra_span_context_t { trace_id_hi, trace_id_lo, span_id }.
 *
 * Implements [CoroutineContext.Element] so it can be propagated through
 * Kotlin coroutine context, enabling structured concurrency-aware tracing:
 *
 * ```kotlin
 * val span = Terra.beginInferenceSpan("gemma-2b")
 * val ctx = span.spanContext()
 * withContext(ctx) {
 *     // Child coroutines can access parent context
 *     val parentCtx = coroutineContext[SpanContext]
 *     val childSpan = Terra.beginToolSpan("search", parent = parentCtx)
 *     // ...
 * }
 * ```
 */
data class SpanContext(
    val traceIdHi: Long,
    val traceIdLo: Long,
    val spanId: Long
) : CoroutineContext.Element {

    companion object Key : CoroutineContext.Key<SpanContext> {

        /** Extract span context from a native span handle via JNI. */
        internal fun fromNativeSpan(spanHandle: Long): SpanContext = SpanContext(
            traceIdHi = nativeGetTraceIdHi(spanHandle),
            traceIdLo = nativeGetTraceIdLo(spanHandle),
            spanId = nativeGetSpanId(spanHandle)
        )

        @JvmStatic private external fun nativeGetTraceIdHi(spanHandle: Long): Long
        @JvmStatic private external fun nativeGetTraceIdLo(spanHandle: Long): Long
        @JvmStatic private external fun nativeGetSpanId(spanHandle: Long): Long
    }

    override val key: CoroutineContext.Key<*> get() = SpanContext

    /** Format trace ID as 32-char hex string (W3C trace-context compatible). */
    fun traceIdHex(): String =
        "%016x%016x".format(traceIdHi, traceIdLo)

    /** Format span ID as 16-char hex string. */
    fun spanIdHex(): String =
        "%016x".format(spanId)

    /** True if this context has a valid (non-zero) trace ID. */
    val isValid: Boolean
        get() = traceIdHi != 0L || traceIdLo != 0L
}
