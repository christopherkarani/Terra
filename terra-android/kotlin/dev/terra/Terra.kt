package dev.terra

import java.util.concurrent.atomic.AtomicLong

/**
 * Terra — On-device GenAI observability SDK (Android).
 *
 * Singleton entry point. Call [init] to start, [shutdown] to tear down.
 * All native methods delegate to libtera via JNI (terra_jni.c).
 */
object Terra {

    init {
        System.loadLibrary("terra")
    }

    /** Opaque pointer to the native terra_t instance, or 0 if not initialized. */
    private val nativeHandle = AtomicLong(0L)

    /* ── Lifecycle ────────────────────────────────────────────────────── */

    /**
     * Initialize Terra with the given configuration.
     * @throws IllegalStateException if already initialized.
     * @throws TerraException on native initialization failure.
     */
    fun init(config: TerraConfig = TerraConfig.Builder().build()) {
        check(nativeHandle.get() == 0L) { "Terra is already initialized" }

        val handle = nativeInit(
            maxSpans = config.maxSpans,
            maxAttributesPerSpan = config.maxAttributesPerSpan,
            maxEventsPerSpan = config.maxEventsPerSpan,
            maxEventAttrs = config.maxEventAttrs,
            batchSize = config.batchSize,
            flushIntervalMs = config.flushIntervalMs,
            contentPolicy = config.contentPolicy.ordinal,
            redactionStrategy = config.redactionStrategy.ordinal,
            hmacKey = config.hmacKey,
            serviceName = config.serviceName,
            serviceVersion = config.serviceVersion,
            otlpEndpoint = config.otlpEndpoint
        )

        if (handle == 0L) {
            val msg = nativeLastErrorMessage() ?: "Unknown native error"
            throw TerraException(nativeLastError(), msg)
        }

        nativeHandle.set(handle)
    }

    /**
     * Initialize Terra with default configuration.
     * @throws IllegalStateException if already initialized.
     * @throws TerraException on native initialization failure.
     */
    fun initDefault() {
        check(nativeHandle.get() == 0L) { "Terra is already initialized" }
        val handle = nativeInitDefault()
        if (handle == 0L) {
            val msg = nativeLastErrorMessage() ?: "Unknown native error"
            throw TerraException(nativeLastError(), msg)
        }
        nativeHandle.set(handle)
    }

    /**
     * Shut down the Terra instance and flush pending telemetry.
     * Safe to call if not initialized (no-op).
     */
    fun shutdown() {
        val handle = nativeHandle.getAndSet(0L)
        if (handle != 0L) {
            val err = nativeShutdown(handle)
            if (err != 0) {
                val msg = nativeLastErrorMessage() ?: "Shutdown failed"
                throw TerraException(err, msg)
            }
        }
    }

    /** Current lifecycle state. */
    val lifecycleState: LifecycleState
        get() {
            val handle = nativeHandle.get()
            if (handle == 0L) return LifecycleState.STOPPED
            return LifecycleState.fromNative(nativeGetState(handle))
        }

    /** True if the instance is in the RUNNING state. */
    val isRunning: Boolean
        get() {
            val handle = nativeHandle.get()
            if (handle == 0L) return false
            return nativeIsRunning(handle)
        }

    /* ── Configuration (runtime) ──────────────────────────────────────── */

    /** Set the session ID for span enrichment. */
    fun setSessionId(sessionId: String) {
        val handle = requireHandle()
        val err = nativeSetSessionId(handle, sessionId)
        if (err != 0) throwNativeError(err)
    }

    /** Set service name and version at runtime. */
    fun setServiceInfo(name: String, version: String) {
        val handle = requireHandle()
        val err = nativeSetServiceInfo(handle, name, version)
        if (err != 0) throwNativeError(err)
    }

    /* ── Span creation ────────────────────────────────────────────────── */

    /** Begin an inference span. Returns a [TerraSpan] to set attributes on. */
    fun beginInferenceSpan(
        model: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): TerraSpan {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginInferenceSpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            model,
            includeContent
        )
        return TerraSpan(handle, spanPtr)
    }

    /** Begin an embedding span. */
    fun beginEmbeddingSpan(
        model: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): TerraSpan {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginEmbeddingSpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            model,
            includeContent
        )
        return TerraSpan(handle, spanPtr)
    }

    /** Begin an agent invocation span. */
    fun beginAgentSpan(
        agentName: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): TerraSpan {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginAgentSpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            agentName,
            includeContent
        )
        return TerraSpan(handle, spanPtr)
    }

    /** Begin a tool execution span. */
    fun beginToolSpan(
        toolName: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): TerraSpan {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginToolSpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            toolName,
            includeContent
        )
        return TerraSpan(handle, spanPtr)
    }

    /** Begin a safety check span. */
    fun beginSafetySpan(
        checkName: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): TerraSpan {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginSafetySpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            checkName,
            includeContent
        )
        return TerraSpan(handle, spanPtr)
    }

    /** Begin a streaming inference span. Returns a [StreamingScope] for token tracking. */
    fun beginStreamingSpan(
        model: String,
        includeContent: Boolean = false,
        parent: SpanContext? = null
    ): StreamingScope {
        val handle = requireHandle()
        val spanPtr = TerraSpan.nativeBeginStreamingSpan(
            handle,
            parent?.traceIdHi ?: 0L,
            parent?.traceIdLo ?: 0L,
            parent?.spanId ?: 0L,
            parent != null,
            model,
            includeContent
        )
        return StreamingScope(handle, spanPtr)
    }

    /* ── Metrics ──────────────────────────────────────────────────────── */

    /** Record an inference duration metric. */
    fun recordInferenceDuration(durationMs: Double) {
        val handle = requireHandle()
        nativeRecordInferenceDuration(handle, durationMs)
    }

    /** Record input/output token counts. */
    fun recordTokenCount(inputTokens: Long, outputTokens: Long) {
        val handle = requireHandle()
        nativeRecordTokenCount(handle, inputTokens, outputTokens)
    }

    /* ── Diagnostics ──────────────────────────────────────────────────── */

    /** Number of spans dropped due to ring buffer overflow. */
    fun spansDropped(): Long {
        val handle = requireHandle()
        return nativeSpansDropped(handle)
    }

    /** True if the transport is in a degraded state. */
    fun transportDegraded(): Boolean {
        val handle = requireHandle()
        return nativeTransportDegraded(handle)
    }

    /** Last error code from the native layer. */
    fun lastError(): Int = nativeLastError()

    /** Last error message from the native layer. */
    fun lastErrorMessage(): String? = nativeLastErrorMessage()

    /** Library version string (e.g., "1.0.0"). */
    fun version(): String = nativeGetVersion()

    /* ── Internal ─────────────────────────────────────────────────────── */

    internal fun requireHandle(): Long {
        val handle = nativeHandle.get()
        check(handle != 0L) { "Terra is not initialized. Call Terra.init() first." }
        return handle
    }

    private fun throwNativeError(code: Int): Nothing {
        val msg = nativeLastErrorMessage() ?: "Native error code $code"
        throw TerraException(code, msg)
    }

    /* ── JNI declarations ─────────────────────────────────────────────── */

    @JvmStatic
    private external fun nativeInit(
        maxSpans: Int,
        maxAttributesPerSpan: Int,
        maxEventsPerSpan: Int,
        maxEventAttrs: Int,
        batchSize: Int,
        flushIntervalMs: Long,
        contentPolicy: Int,
        redactionStrategy: Int,
        hmacKey: String?,
        serviceName: String,
        serviceVersion: String,
        otlpEndpoint: String
    ): Long

    @JvmStatic private external fun nativeInitDefault(): Long
    @JvmStatic private external fun nativeShutdown(handle: Long): Int
    @JvmStatic private external fun nativeGetState(handle: Long): Int
    @JvmStatic private external fun nativeIsRunning(handle: Long): Boolean
    @JvmStatic private external fun nativeSetSessionId(handle: Long, sessionId: String): Int
    @JvmStatic private external fun nativeSetServiceInfo(handle: Long, name: String, version: String): Int
    @JvmStatic private external fun nativeLastError(): Int
    @JvmStatic private external fun nativeLastErrorMessage(): String?
    @JvmStatic private external fun nativeSpansDropped(handle: Long): Long
    @JvmStatic private external fun nativeTransportDegraded(handle: Long): Boolean
    @JvmStatic private external fun nativeGetVersion(): String
    @JvmStatic private external fun nativeRecordInferenceDuration(handle: Long, durationMs: Double)
    @JvmStatic private external fun nativeRecordTokenCount(handle: Long, inputTokens: Long, outputTokens: Long)
}

/** Lifecycle states matching terra_lifecycle_state_t. */
enum class LifecycleState {
    STOPPED,
    STARTING,
    RUNNING,
    SHUTTING_DOWN;

    companion object {
        fun fromNative(value: Int): LifecycleState = entries.getOrElse(value) { STOPPED }
    }
}

/** Exception wrapping Terra native error codes. */
class TerraException(val errorCode: Int, message: String) : RuntimeException("Terra error $errorCode: $message")
