package dev.terra

/**
 * StreamingScope — Wraps a streaming inference span for token-level tracking.
 *
 * Usage:
 * ```kotlin
 * val stream = Terra.beginStreamingSpan("gemma-2b")
 * stream.use { scope ->
 *     for (token in tokenStream) {
 *         if (scope.tokenCount == 0L) scope.recordFirstToken()
 *         scope.recordToken()
 *         // process token...
 *     }
 * }
 * // span is automatically ended with streaming metrics
 * ```
 *
 * Tracks: time-to-first-token (TTFT), token count, and derived tokens/second.
 */
class StreamingScope internal constructor(
    private val instHandle: Long,
    private val spanHandle: Long
) {
    private var finished = false
    private var _tokenCount: Long = 0L

    /** Number of tokens recorded so far. */
    val tokenCount: Long get() = _tokenCount

    /** Record receipt of a token (increments token count). */
    fun recordToken() {
        checkNotFinished()
        _tokenCount++
        nativeRecordToken(spanHandle)
    }

    /** Record the first token timestamp (TTFT measurement). Call once. */
    fun recordFirstToken() {
        checkNotFinished()
        nativeRecordFirstToken(spanHandle)
    }

    /**
     * Set an attribute on the underlying span.
     * Delegates to the span mutation API.
     */
    fun setAttribute(key: String, value: String): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeSetString(spanHandle, key, value)
        return this
    }

    fun setAttribute(key: String, value: Long): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeSetInt(spanHandle, key, value)
        return this
    }

    fun setAttribute(key: String, value: Double): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeSetDouble(spanHandle, key, value)
        return this
    }

    fun setAttribute(key: String, value: Boolean): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeSetBool(spanHandle, key, value)
        return this
    }

    /** Add a named event to the underlying span. */
    fun addEvent(name: String): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeAddEvent(spanHandle, name)
        return this
    }

    /** Record an error on the underlying span. */
    fun recordError(
        type: String,
        message: String,
        setStatus: Boolean = true
    ): StreamingScope {
        checkNotFinished()
        TerraSpan.nativeRecordError(spanHandle, type, message, setStatus)
        return this
    }

    /** Extract span context for parent-child propagation. */
    fun spanContext(): SpanContext {
        checkNotFinished()
        return SpanContext.fromNativeSpan(spanHandle)
    }

    /**
     * Finish the streaming span. Finalizes streaming metrics
     * (TTFT, token count, tokens/second) and ends the span.
     * Must be called exactly once.
     */
    fun finish() {
        checkNotFinished()
        finished = true
        nativeEnd(spanHandle)
        TerraSpan.nativeEnd(instHandle, spanHandle)
    }

    /** Use as a scoped block — auto-finishes on exit. */
    inline fun <R> use(block: (StreamingScope) -> R): R {
        try {
            return block(this)
        } catch (e: Throwable) {
            recordError(e.javaClass.name, e.message ?: "Unknown error")
            throw e
        } finally {
            if (!finished) finish()
        }
    }

    private fun checkNotFinished() {
        check(!finished) { "StreamingScope has already been finished" }
    }

    /* ── JNI declarations ─────────────────────────────────────────────── */

    companion object {
        @JvmStatic private external fun nativeRecordToken(spanHandle: Long)
        @JvmStatic private external fun nativeRecordFirstToken(spanHandle: Long)
        @JvmStatic private external fun nativeEnd(spanHandle: Long)
    }
}
