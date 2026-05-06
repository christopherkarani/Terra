package dev.terra

/**
 * TerraSpan — Wrapper around a native terra_span_t handle.
 *
 * Provides type-safe attribute setting, event recording, error recording,
 * and span termination. Must be [end]ed to finalize the span.
 *
 * Not thread-safe: a single span should be mutated from one thread at a time.
 * The underlying Zig core handles concurrent span creation safely.
 */
class TerraSpan internal constructor(
    private val instHandle: Long,
    private val spanHandle: Long
) {
    private var ended = false

    /* ── Attributes ───────────────────────────────────────────────────── */

    /** Set a string attribute on this span. */
    fun setAttribute(key: String, value: String): TerraSpan {
        checkNotEnded()
        setString(spanHandle, key, value)
        return this
    }

    /** Set an integer attribute on this span. */
    fun setAttribute(key: String, value: Long): TerraSpan {
        checkNotEnded()
        setInt(spanHandle, key, value)
        return this
    }

    /** Set a double attribute on this span. */
    fun setAttribute(key: String, value: Double): TerraSpan {
        checkNotEnded()
        setDouble(spanHandle, key, value)
        return this
    }

    /** Set a boolean attribute on this span. */
    fun setAttribute(key: String, value: Boolean): TerraSpan {
        checkNotEnded()
        setBool(spanHandle, key, value)
        return this
    }

    /* ── Status ───────────────────────────────────────────────────────── */

    /** Set the span status. See [StatusCode] for valid values. */
    fun setStatus(code: StatusCode, description: String? = null): TerraSpan {
        checkNotEnded()
        setStatusNative(spanHandle, code.value, description)
        return this
    }

    /* ── Events ───────────────────────────────────────────────────────── */

    /** Add a named event at the current timestamp. */
    fun addEvent(name: String): TerraSpan {
        checkNotEnded()
        addEventNative(spanHandle, name)
        return this
    }

    /** Add a named event at a specific timestamp (nanoseconds since epoch). */
    fun addEvent(name: String, timestampNs: Long): TerraSpan {
        checkNotEnded()
        addEventTimestamp(spanHandle, name, timestampNs)
        return this
    }

    /* ── Error recording ──────────────────────────────────────────────── */

    /**
     * Record an error on this span.
     * @param type Error type (e.g., exception class name).
     * @param message Human-readable error message.
     * @param setStatus If true, also sets span status to ERROR.
     */
    fun recordError(
        type: String,
        message: String,
        setStatus: Boolean = true
    ): TerraSpan {
        checkNotEnded()
        recordErrorNative(spanHandle, type, message, setStatus)
        return this
    }

    /* ── Context ──────────────────────────────────────────────────────── */

    /** Extract the span context for parent-child propagation. */
    fun spanContext(): SpanContext {
        checkNotEnded()
        return SpanContext.fromNativeSpan(spanHandle)
    }

    /* ── Termination ──────────────────────────────────────────────────── */

    /** End this span. Must be called exactly once. */
    fun end() {
        checkNotEnded()
        ended = true
        endNative(instHandle, spanHandle)
    }

    /** Use as a try-with-resources style block. */
    fun <R> use(block: (TerraSpan) -> R): R {
        try {
            return block(this)
        } catch (e: Throwable) {
            if (!ended) {
                recordError(e.javaClass.name, e.message ?: "Unknown error")
            }
            throw e
        } finally {
            if (!ended) end()
        }
    }

    private fun checkNotEnded() {
        check(!ended) { "Span has already been ended" }
    }

    /* ── JNI declarations ─────────────────────────────────────────────── */

    companion object {
        @JvmStatic
        private external fun nativeBeginInferenceSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        private external fun nativeBeginEmbeddingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        private external fun nativeBeginAgentSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, agentName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        private external fun nativeBeginToolSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, toolName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        private external fun nativeBeginSafetySpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, checkName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        private external fun nativeBeginStreamingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic private external fun nativeSetString(spanHandle: Long, key: String, value: String)
        @JvmStatic private external fun nativeSetInt(spanHandle: Long, key: String, value: Long)
        @JvmStatic private external fun nativeSetDouble(spanHandle: Long, key: String, value: Double)
        @JvmStatic private external fun nativeSetBool(spanHandle: Long, key: String, value: Boolean)
        @JvmStatic private external fun nativeSetStatus(spanHandle: Long, statusCode: Int, description: String?)
        @JvmStatic private external fun nativeEnd(instHandle: Long, spanHandle: Long)
        @JvmStatic private external fun nativeAddEvent(spanHandle: Long, name: String)
        @JvmStatic private external fun nativeAddEventTs(spanHandle: Long, name: String, timestampNs: Long)
        @JvmStatic private external fun nativeRecordError(spanHandle: Long, errorType: String, errorMessage: String, setStatus: Boolean)

        @JvmStatic
        internal fun beginInferenceSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long = nativeBeginInferenceSpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, model, includeContent
        )

        @JvmStatic
        internal fun beginEmbeddingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long = nativeBeginEmbeddingSpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, model, includeContent
        )

        @JvmStatic
        internal fun beginAgentSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, agentName: String,
            includeContent: Boolean
        ): Long = nativeBeginAgentSpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, agentName, includeContent
        )

        @JvmStatic
        internal fun beginToolSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, toolName: String,
            includeContent: Boolean
        ): Long = nativeBeginToolSpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, toolName, includeContent
        )

        @JvmStatic
        internal fun beginSafetySpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, checkName: String,
            includeContent: Boolean
        ): Long = nativeBeginSafetySpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, checkName, includeContent
        )

        @JvmStatic
        internal fun beginStreamingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long = nativeBeginStreamingSpan(
            instHandle, traceIdHi, traceIdLo, parentSpanId, hasParent, model, includeContent
        )

        @JvmStatic internal fun setString(spanHandle: Long, key: String, value: String) = nativeSetString(spanHandle, key, value)
        @JvmStatic internal fun setInt(spanHandle: Long, key: String, value: Long) = nativeSetInt(spanHandle, key, value)
        @JvmStatic internal fun setDouble(spanHandle: Long, key: String, value: Double) = nativeSetDouble(spanHandle, key, value)
        @JvmStatic internal fun setBool(spanHandle: Long, key: String, value: Boolean) = nativeSetBool(spanHandle, key, value)
        @JvmStatic internal fun setStatusNative(spanHandle: Long, statusCode: Int, description: String?) = nativeSetStatus(spanHandle, statusCode, description)
        @JvmStatic internal fun endNative(instHandle: Long, spanHandle: Long) = nativeEnd(instHandle, spanHandle)
        @JvmStatic internal fun addEventNative(spanHandle: Long, name: String) = nativeAddEvent(spanHandle, name)
        @JvmStatic internal fun addEventTimestamp(spanHandle: Long, name: String, timestampNs: Long) = nativeAddEventTs(spanHandle, name, timestampNs)
        @JvmStatic internal fun recordErrorNative(spanHandle: Long, errorType: String, errorMessage: String, setStatus: Boolean) = nativeRecordError(spanHandle, errorType, errorMessage, setStatus)
    }
}

/** Status codes matching terra_status_code_t. */
enum class StatusCode(val value: Int) {
    UNSET(0),
    OK(1),
    ERROR(2);
}
