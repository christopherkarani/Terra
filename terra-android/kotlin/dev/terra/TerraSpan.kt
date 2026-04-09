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
        nativeSetString(spanHandle, key, value)
        return this
    }

    /** Set an integer attribute on this span. */
    fun setAttribute(key: String, value: Long): TerraSpan {
        checkNotEnded()
        nativeSetInt(spanHandle, key, value)
        return this
    }

    /** Set a double attribute on this span. */
    fun setAttribute(key: String, value: Double): TerraSpan {
        checkNotEnded()
        nativeSetDouble(spanHandle, key, value)
        return this
    }

    /** Set a boolean attribute on this span. */
    fun setAttribute(key: String, value: Boolean): TerraSpan {
        checkNotEnded()
        nativeSetBool(spanHandle, key, value)
        return this
    }

    /* ── Status ───────────────────────────────────────────────────────── */

    /** Set the span status. See [StatusCode] for valid values. */
    fun setStatus(code: StatusCode, description: String? = null): TerraSpan {
        checkNotEnded()
        nativeSetStatus(spanHandle, code.value, description)
        return this
    }

    /* ── Events ───────────────────────────────────────────────────────── */

    /** Add a named event at the current timestamp. */
    fun addEvent(name: String): TerraSpan {
        checkNotEnded()
        nativeAddEvent(spanHandle, name)
        return this
    }

    /** Add a named event at a specific timestamp (nanoseconds since epoch). */
    fun addEvent(name: String, timestampNs: Long): TerraSpan {
        checkNotEnded()
        nativeAddEventTs(spanHandle, name, timestampNs)
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
        nativeRecordError(spanHandle, type, message, setStatus)
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
        nativeEnd(instHandle, spanHandle)
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
        internal external fun nativeBeginInferenceSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        internal external fun nativeBeginEmbeddingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        internal external fun nativeBeginAgentSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, agentName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        internal external fun nativeBeginToolSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, toolName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        internal external fun nativeBeginSafetySpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, checkName: String,
            includeContent: Boolean
        ): Long

        @JvmStatic
        internal external fun nativeBeginStreamingSpan(
            instHandle: Long, traceIdHi: Long, traceIdLo: Long,
            parentSpanId: Long, hasParent: Boolean, model: String,
            includeContent: Boolean
        ): Long

        @JvmStatic internal external fun nativeSetString(spanHandle: Long, key: String, value: String)
        @JvmStatic internal external fun nativeSetInt(spanHandle: Long, key: String, value: Long)
        @JvmStatic internal external fun nativeSetDouble(spanHandle: Long, key: String, value: Double)
        @JvmStatic internal external fun nativeSetBool(spanHandle: Long, key: String, value: Boolean)
        @JvmStatic internal external fun nativeSetStatus(spanHandle: Long, statusCode: Int, description: String?)
        @JvmStatic internal external fun nativeEnd(instHandle: Long, spanHandle: Long)
        @JvmStatic internal external fun nativeAddEvent(spanHandle: Long, name: String)
        @JvmStatic internal external fun nativeAddEventTs(spanHandle: Long, name: String, timestampNs: Long)
        @JvmStatic internal external fun nativeRecordError(spanHandle: Long, errorType: String, errorMessage: String, setStatus: Boolean)
    }
}

/** Status codes matching terra_status_code_t. */
enum class StatusCode(val value: Int) {
    UNSET(0),
    OK(1),
    ERROR(2);
}
