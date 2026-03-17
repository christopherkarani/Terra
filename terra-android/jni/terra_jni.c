/*
 * terra_jni.c — JNI bridge mapping terra.h → JNI native methods
 *
 * Every terra.h function is mapped to a JNI method callable from Kotlin.
 * Opaque pointers (terra_t*, terra_span_t*) are passed as jlong via
 * (jlong)(intptr_t)ptr casts.
 */

#include <jni.h>
#include <stdint.h>
#include <string.h>
#include "terra.h"

/* ── Pointer cast helpers ─────────────────────────────────────────────── */

#define PTR_TO_JLONG(p)   ((jlong)(intptr_t)(p))
#define JLONG_TO_INST(j)  ((terra_t *)(intptr_t)(j))
#define JLONG_TO_SPAN(j)  ((terra_span_t *)(intptr_t)(j))

/* ── JNI helpers ──────────────────────────────────────────────────────── */

/**
 * Get a UTF-8 C string from a jstring, returning NULL if jstr is NULL.
 * Caller must release with (*env)->ReleaseStringUTFChars if non-NULL.
 */
static const char *jstr_to_c(JNIEnv *env, jstring jstr) {
    if (jstr == NULL) return NULL;
    return (*env)->GetStringUTFChars(env, jstr, NULL);
}

static void release_jstr(JNIEnv *env, jstring jstr, const char *cstr) {
    if (jstr != NULL && cstr != NULL) {
        (*env)->ReleaseStringUTFChars(env, jstr, cstr);
    }
}

/* ── Lifecycle ────────────────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_dev_terra_Terra_nativeInit(JNIEnv *env, jclass clazz,
                                 jint maxSpans,
                                 jint maxAttributesPerSpan,
                                 jint maxEventsPerSpan,
                                 jint maxEventAttrs,
                                 jint batchSize,
                                 jlong flushIntervalMs,
                                 jint contentPolicy,
                                 jint redactionStrategy,
                                 jstring hmacKey,
                                 jstring serviceName,
                                 jstring serviceVersion,
                                 jstring otlpEndpoint) {
    (void)clazz;

    const char *c_hmac_key   = jstr_to_c(env, hmacKey);
    const char *c_svc_name   = jstr_to_c(env, serviceName);
    const char *c_svc_ver    = jstr_to_c(env, serviceVersion);
    const char *c_endpoint   = jstr_to_c(env, otlpEndpoint);

    terra_config_t config;
    memset(&config, 0, sizeof(config));

    config.max_spans              = (uint32_t)maxSpans;
    config.max_attributes_per_span = (uint16_t)maxAttributesPerSpan;
    config.max_events_per_span    = (uint16_t)maxEventsPerSpan;
    config.max_event_attrs        = (uint16_t)maxEventAttrs;
    config.batch_size             = (uint32_t)batchSize;
    config.flush_interval_ms      = (uint64_t)flushIntervalMs;
    config.content_policy         = (terra_content_policy_t)contentPolicy;
    config.redaction_strategy     = (terra_redaction_strategy_t)redactionStrategy;
    config.hmac_key               = c_hmac_key;
    config.service_name           = c_svc_name;
    config.service_version        = c_svc_ver;
    config.otlp_endpoint          = c_endpoint;

    /* Transport, scheduler, storage, and clock vtables are NULL (zeroed) —
       Kotlin-side transport is injected separately via nativeSetTransport. */

    terra_t *inst = terra_init(&config);

    release_jstr(env, hmacKey, c_hmac_key);
    release_jstr(env, serviceName, c_svc_name);
    release_jstr(env, serviceVersion, c_svc_ver);
    release_jstr(env, otlpEndpoint, c_endpoint);

    return PTR_TO_JLONG(inst);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_Terra_nativeInitDefault(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    terra_t *inst = terra_init(NULL);
    return PTR_TO_JLONG(inst);
}

JNIEXPORT jint JNICALL
Java_dev_terra_Terra_nativeShutdown(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return (jint)terra_shutdown(JLONG_TO_INST(handle));
}

JNIEXPORT jint JNICALL
Java_dev_terra_Terra_nativeGetState(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return (jint)terra_get_state(JLONG_TO_INST(handle));
}

JNIEXPORT jboolean JNICALL
Java_dev_terra_Terra_nativeIsRunning(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return (jboolean)terra_is_running(JLONG_TO_INST(handle));
}

/* ── Configuration (runtime) ──────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_dev_terra_Terra_nativeSetSessionId(JNIEnv *env, jclass clazz,
                                         jlong handle, jstring sessionId) {
    (void)clazz;
    const char *c_sid = jstr_to_c(env, sessionId);
    int result = terra_set_session_id(JLONG_TO_INST(handle), c_sid);
    release_jstr(env, sessionId, c_sid);
    return (jint)result;
}

JNIEXPORT jint JNICALL
Java_dev_terra_Terra_nativeSetServiceInfo(JNIEnv *env, jclass clazz,
                                           jlong handle,
                                           jstring name, jstring version) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, name);
    const char *c_ver  = jstr_to_c(env, version);
    int result = terra_set_service_info(JLONG_TO_INST(handle), c_name, c_ver);
    release_jstr(env, name, c_name);
    release_jstr(env, version, c_ver);
    return (jint)result;
}

/* ── Span creation ────────────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginInferenceSpan(JNIEnv *env, jclass clazz,
                                                    jlong instHandle,
                                                    jlong traceIdHi,
                                                    jlong traceIdLo,
                                                    jlong parentSpanId,
                                                    jboolean hasParent,
                                                    jstring model,
                                                    jboolean includeContent) {
    (void)clazz;
    const char *c_model = jstr_to_c(env, model);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_inference_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_model, (bool)includeContent);

    release_jstr(env, model, c_model);
    return PTR_TO_JLONG(span);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginEmbeddingSpan(JNIEnv *env, jclass clazz,
                                                    jlong instHandle,
                                                    jlong traceIdHi,
                                                    jlong traceIdLo,
                                                    jlong parentSpanId,
                                                    jboolean hasParent,
                                                    jstring model,
                                                    jboolean includeContent) {
    (void)clazz;
    const char *c_model = jstr_to_c(env, model);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_embedding_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_model, (bool)includeContent);

    release_jstr(env, model, c_model);
    return PTR_TO_JLONG(span);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginAgentSpan(JNIEnv *env, jclass clazz,
                                                jlong instHandle,
                                                jlong traceIdHi,
                                                jlong traceIdLo,
                                                jlong parentSpanId,
                                                jboolean hasParent,
                                                jstring agentName,
                                                jboolean includeContent) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, agentName);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_agent_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_name, (bool)includeContent);

    release_jstr(env, agentName, c_name);
    return PTR_TO_JLONG(span);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginToolSpan(JNIEnv *env, jclass clazz,
                                               jlong instHandle,
                                               jlong traceIdHi,
                                               jlong traceIdLo,
                                               jlong parentSpanId,
                                               jboolean hasParent,
                                               jstring toolName,
                                               jboolean includeContent) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, toolName);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_tool_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_name, (bool)includeContent);

    release_jstr(env, toolName, c_name);
    return PTR_TO_JLONG(span);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginSafetySpan(JNIEnv *env, jclass clazz,
                                                 jlong instHandle,
                                                 jlong traceIdHi,
                                                 jlong traceIdLo,
                                                 jlong parentSpanId,
                                                 jboolean hasParent,
                                                 jstring checkName,
                                                 jboolean includeContent) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, checkName);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_safety_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_name, (bool)includeContent);

    release_jstr(env, checkName, c_name);
    return PTR_TO_JLONG(span);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_TerraSpan_nativeBeginStreamingSpan(JNIEnv *env, jclass clazz,
                                                    jlong instHandle,
                                                    jlong traceIdHi,
                                                    jlong traceIdLo,
                                                    jlong parentSpanId,
                                                    jboolean hasParent,
                                                    jstring model,
                                                    jboolean includeContent) {
    (void)clazz;
    const char *c_model = jstr_to_c(env, model);

    const terra_span_context_t *parent_ctx = NULL;
    terra_span_context_t ctx;
    if (hasParent) {
        ctx.trace_id_hi = (uint64_t)traceIdHi;
        ctx.trace_id_lo = (uint64_t)traceIdLo;
        ctx.span_id     = (uint64_t)parentSpanId;
        parent_ctx = &ctx;
    }

    terra_span_t *span = terra_begin_streaming_span_ctx(
        JLONG_TO_INST(instHandle), parent_ctx, c_model, (bool)includeContent);

    release_jstr(env, model, c_model);
    return PTR_TO_JLONG(span);
}

/* ── Span mutation ────────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeSetString(JNIEnv *env, jclass clazz,
                                          jlong spanHandle,
                                          jstring key, jstring value) {
    (void)clazz;
    const char *c_key = jstr_to_c(env, key);
    const char *c_val = jstr_to_c(env, value);
    terra_span_set_string(JLONG_TO_SPAN(spanHandle), c_key, c_val);
    release_jstr(env, key, c_key);
    release_jstr(env, value, c_val);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeSetInt(JNIEnv *env, jclass clazz,
                                       jlong spanHandle,
                                       jstring key, jlong value) {
    (void)clazz;
    const char *c_key = jstr_to_c(env, key);
    terra_span_set_int(JLONG_TO_SPAN(spanHandle), c_key, (int64_t)value);
    release_jstr(env, key, c_key);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeSetDouble(JNIEnv *env, jclass clazz,
                                          jlong spanHandle,
                                          jstring key, jdouble value) {
    (void)clazz;
    const char *c_key = jstr_to_c(env, key);
    terra_span_set_double(JLONG_TO_SPAN(spanHandle), c_key, (double)value);
    release_jstr(env, key, c_key);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeSetBool(JNIEnv *env, jclass clazz,
                                        jlong spanHandle,
                                        jstring key, jboolean value) {
    (void)clazz;
    const char *c_key = jstr_to_c(env, key);
    terra_span_set_bool(JLONG_TO_SPAN(spanHandle), c_key, (bool)value);
    release_jstr(env, key, c_key);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeSetStatus(JNIEnv *env, jclass clazz,
                                          jlong spanHandle,
                                          jint statusCode,
                                          jstring description) {
    (void)clazz;
    const char *c_desc = jstr_to_c(env, description);
    terra_span_set_status(JLONG_TO_SPAN(spanHandle), (uint8_t)statusCode, c_desc);
    release_jstr(env, description, c_desc);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeEnd(JNIEnv *env, jclass clazz,
                                    jlong instHandle, jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_span_end(JLONG_TO_INST(instHandle), JLONG_TO_SPAN(spanHandle));
}

/* ── Events ───────────────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeAddEvent(JNIEnv *env, jclass clazz,
                                         jlong spanHandle, jstring name) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, name);
    terra_span_add_event(JLONG_TO_SPAN(spanHandle), c_name);
    release_jstr(env, name, c_name);
}

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeAddEventTs(JNIEnv *env, jclass clazz,
                                            jlong spanHandle,
                                            jstring name,
                                            jlong timestampNs) {
    (void)clazz;
    const char *c_name = jstr_to_c(env, name);
    terra_span_add_event_ts(JLONG_TO_SPAN(spanHandle), c_name, (uint64_t)timestampNs);
    release_jstr(env, name, c_name);
}

/* ── Error recording ──────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_dev_terra_TerraSpan_nativeRecordError(JNIEnv *env, jclass clazz,
                                            jlong spanHandle,
                                            jstring errorType,
                                            jstring errorMessage,
                                            jboolean setStatus) {
    (void)clazz;
    const char *c_type = jstr_to_c(env, errorType);
    const char *c_msg  = jstr_to_c(env, errorMessage);
    terra_span_record_error(JLONG_TO_SPAN(spanHandle), c_type, c_msg, (bool)setStatus);
    release_jstr(env, errorType, c_type);
    release_jstr(env, errorMessage, c_msg);
}

/* ── Streaming ────────────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_dev_terra_StreamingScope_nativeRecordToken(JNIEnv *env, jclass clazz,
                                                 jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_streaming_record_token(JLONG_TO_SPAN(spanHandle));
}

JNIEXPORT void JNICALL
Java_dev_terra_StreamingScope_nativeRecordFirstToken(JNIEnv *env, jclass clazz,
                                                      jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_streaming_record_first_token(JLONG_TO_SPAN(spanHandle));
}

JNIEXPORT void JNICALL
Java_dev_terra_StreamingScope_nativeEnd(JNIEnv *env, jclass clazz,
                                         jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_streaming_end(JLONG_TO_SPAN(spanHandle));
}

/* ── Context extraction ───────────────────────────────────────────────── */

JNIEXPORT jlong JNICALL
Java_dev_terra_SpanContext_nativeGetTraceIdHi(JNIEnv *env, jclass clazz,
                                               jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_span_context_t ctx = terra_span_context(JLONG_TO_SPAN(spanHandle));
    return (jlong)ctx.trace_id_hi;
}

JNIEXPORT jlong JNICALL
Java_dev_terra_SpanContext_nativeGetTraceIdLo(JNIEnv *env, jclass clazz,
                                               jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_span_context_t ctx = terra_span_context(JLONG_TO_SPAN(spanHandle));
    return (jlong)ctx.trace_id_lo;
}

JNIEXPORT jlong JNICALL
Java_dev_terra_SpanContext_nativeGetSpanId(JNIEnv *env, jclass clazz,
                                            jlong spanHandle) {
    (void)env;
    (void)clazz;
    terra_span_context_t ctx = terra_span_context(JLONG_TO_SPAN(spanHandle));
    return (jlong)ctx.span_id;
}

/* ── Diagnostics ──────────────────────────────────────────────────────── */

JNIEXPORT jint JNICALL
Java_dev_terra_Terra_nativeLastError(JNIEnv *env, jclass clazz) {
    (void)env;
    (void)clazz;
    return (jint)terra_last_error();
}

JNIEXPORT jstring JNICALL
Java_dev_terra_Terra_nativeLastErrorMessage(JNIEnv *env, jclass clazz) {
    (void)clazz;
    char buf[1024];
    uint32_t len = terra_last_error_message(buf, (uint32_t)sizeof(buf));
    if (len == 0) return NULL;
    return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jlong JNICALL
Java_dev_terra_Terra_nativeSpansDropped(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return (jlong)terra_spans_dropped(JLONG_TO_INST(handle));
}

JNIEXPORT jboolean JNICALL
Java_dev_terra_Terra_nativeTransportDegraded(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return (jboolean)terra_transport_degraded(JLONG_TO_INST(handle));
}

/* ── Version ──────────────────────────────────────────────────────────── */

JNIEXPORT jstring JNICALL
Java_dev_terra_Terra_nativeGetVersion(JNIEnv *env, jclass clazz) {
    (void)clazz;
    terra_version_t v = terra_get_version();
    char buf[64];
    snprintf(buf, sizeof(buf), "%u.%u.%u", v.major, v.minor, v.patch);
    return (*env)->NewStringUTF(env, buf);
}

/* ── Metrics ──────────────────────────────────────────────────────────── */

JNIEXPORT void JNICALL
Java_dev_terra_Terra_nativeRecordInferenceDuration(JNIEnv *env, jclass clazz,
                                                     jlong handle,
                                                     jdouble durationMs) {
    (void)env;
    (void)clazz;
    terra_record_inference_duration(JLONG_TO_INST(handle), (double)durationMs);
}

JNIEXPORT void JNICALL
Java_dev_terra_Terra_nativeRecordTokenCount(JNIEnv *env, jclass clazz,
                                              jlong handle,
                                              jlong inputTokens,
                                              jlong outputTokens) {
    (void)env;
    (void)clazz;
    terra_record_token_count(JLONG_TO_INST(handle),
                              (int64_t)inputTokens,
                              (int64_t)outputTokens);
}
