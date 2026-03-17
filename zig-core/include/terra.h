/*
 * terra.h — C ABI header for Terra Zig Core
 *
 * Manually maintained. Must match exports in src/c_api.zig exactly.
 * This is the single public header for embedding Terra in C/Swift/ObjC hosts.
 */

#ifndef TERRA_H
#define TERRA_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── ABI version ───────────────────────────────────────────────────────── */

#define TERRA_ABI_VERSION_MAJOR 1
#define TERRA_ABI_VERSION_MINOR 0
#define TERRA_ABI_VERSION_PATCH 0

/* ── Opaque handles ────────────────────────────────────────────────────── */

typedef struct terra_s       terra_t;
typedef struct terra_span_s  terra_span_t;
typedef struct terra_scope_s terra_scope_t;

/* ── Error codes ───────────────────────────────────────────────────────── */

typedef enum {
    TERRA_OK                    = 0,
    TERRA_ERR_ALREADY_INITIALIZED = 1,
    TERRA_ERR_NOT_INITIALIZED   = 2,
    TERRA_ERR_INVALID_CONFIG    = 3,
    TERRA_ERR_OUT_OF_MEMORY     = 4,
    TERRA_ERR_TRANSPORT_FAILED  = 5,
    TERRA_ERR_SHUTTING_DOWN     = 6,
} terra_error_t;

/* ── Lifecycle state ───────────────────────────────────────────────────── */

typedef enum {
    TERRA_STATE_STOPPED       = 0,
    TERRA_STATE_STARTING      = 1,
    TERRA_STATE_RUNNING        = 2,
    TERRA_STATE_SHUTTING_DOWN  = 3,
} terra_lifecycle_state_t;

/* ── Content policy ────────────────────────────────────────────────────── */

typedef enum {
    TERRA_CONTENT_NEVER  = 0,
    TERRA_CONTENT_OPT_IN = 1,
    TERRA_CONTENT_ALWAYS = 2,
} terra_content_policy_t;

/* ── Redaction strategy ────────────────────────────────────────────────── */

typedef enum {
    TERRA_REDACT_DROP        = 0,
    TERRA_REDACT_LENGTH_ONLY = 1,
    TERRA_REDACT_HMAC_SHA256 = 2,
} terra_redaction_strategy_t;

/* ── Status code ───────────────────────────────────────────────────────── */

typedef enum {
    TERRA_STATUS_UNSET = 0,
    TERRA_STATUS_OK    = 1,
    TERRA_STATUS_ERROR = 2,
} terra_status_code_t;

/* ── Span context (flat, ABI-stable) ───────────────────────────────────── */

typedef struct {
    uint64_t trace_id_hi;
    uint64_t trace_id_lo;
    uint64_t span_id;
} terra_span_context_t;

/* ── Version ───────────────────────────────────────────────────────────── */

typedef struct {
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} terra_version_t;

/* ── Transport VTable ──────────────────────────────────────────────────── */

typedef int  (*terra_send_fn)(const uint8_t *data, uint32_t len, void *ctx);
typedef void (*terra_flush_fn)(void *ctx);
typedef void (*terra_shutdown_fn)(void *ctx);

typedef struct {
    terra_send_fn     send_fn;
    terra_flush_fn    flush_fn;
    terra_shutdown_fn shutdown_fn;
    void             *context;
} terra_transport_vtable_t;

/* ── Scheduler VTable ──────────────────────────────────────────────────── */

typedef void (*terra_scheduler_callback_fn)(void *ctx);
typedef uint64_t (*terra_schedule_fn)(terra_scheduler_callback_fn callback,
                                      uint64_t interval_ms,
                                      void *cb_ctx,
                                      void *ctx);
typedef void (*terra_cancel_fn)(uint64_t handle, void *ctx);

typedef struct {
    terra_schedule_fn schedule_fn;
    terra_cancel_fn   cancel_fn;
    void             *context;
} terra_scheduler_vtable_t;

/* ── Storage VTable ────────────────────────────────────────────────────── */

typedef int      (*terra_storage_write_fn)(const uint8_t *data, uint32_t len, void *ctx);
typedef uint32_t (*terra_storage_read_fn)(uint8_t *buf, uint32_t max_len, void *ctx);
typedef void     (*terra_storage_discard_oldest_fn)(uint32_t bytes, void *ctx);
typedef uint64_t (*terra_storage_available_bytes_fn)(void *ctx);

typedef struct {
    terra_storage_write_fn           write_fn;
    terra_storage_read_fn            read_fn;
    terra_storage_discard_oldest_fn  discard_oldest_fn;
    terra_storage_available_bytes_fn available_bytes_fn;
    void                            *context;
} terra_storage_vtable_t;

/* ── Clock function ────────────────────────────────────────────────────── */

typedef uint64_t (*terra_clock_fn)(void *ctx);

/* ── Configuration ─────────────────────────────────────────────────────── */

typedef struct {
    /* Ring buffer capacity */
    uint32_t max_spans;
    /* Attribute / event limits */
    uint16_t max_attributes_per_span;
    uint16_t max_events_per_span;
    uint16_t max_event_attrs;
    /* Batching */
    uint32_t batch_size;
    uint64_t flush_interval_ms;
    /* Privacy */
    terra_content_policy_t    content_policy;
    terra_redaction_strategy_t redaction_strategy;
    const char *hmac_key;            /* null-terminated, nullable */
    bool        emit_legacy_sha256;
    /* Service metadata */
    const char *service_name;        /* null-terminated */
    const char *service_version;     /* null-terminated */
    /* OTLP endpoint */
    const char *otlp_endpoint;       /* null-terminated */
    /* Clock */
    terra_clock_fn clock_fn;
    void          *clock_ctx;
    /* VTables */
    terra_transport_vtable_t transport_vtable;
    terra_scheduler_vtable_t scheduler_vtable;
    terra_storage_vtable_t   storage_vtable;
} terra_config_t;

/* ── Lifecycle ─────────────────────────────────────────────────────────── */

/**
 * Create and initialize a Terra instance.
 * Pass NULL for default configuration.
 * Returns NULL on failure (call terra_last_error for details).
 */
terra_t *terra_init(const terra_config_t *config);

/**
 * Shut down and destroy a Terra instance.
 * Returns TERRA_OK on success.
 */
int terra_shutdown(terra_t *inst);

/**
 * Get the current lifecycle state (returns terra_lifecycle_state_t as uint8_t).
 */
uint8_t terra_get_state(const terra_t *inst);

/**
 * Returns true if the instance is in the RUNNING state.
 */
bool terra_is_running(const terra_t *inst);

/* ── Configuration (runtime) ───────────────────────────────────────────── */

int terra_set_session_id(terra_t *inst, const char *session_id);
int terra_set_service_info(terra_t *inst, const char *name, const char *version);

/* ── Span creation (parent by context) ─────────────────────────────────── */

terra_span_t *terra_begin_inference_span_ctx(terra_t *inst,
                                              const terra_span_context_t *parent_ctx,
                                              const char *model,
                                              bool include_content);

terra_span_t *terra_begin_embedding_span_ctx(terra_t *inst,
                                              const terra_span_context_t *parent_ctx,
                                              const char *model,
                                              bool include_content);

terra_span_t *terra_begin_agent_span_ctx(terra_t *inst,
                                          const terra_span_context_t *parent_ctx,
                                          const char *agent_name,
                                          bool include_content);

terra_span_t *terra_begin_tool_span_ctx(terra_t *inst,
                                         const terra_span_context_t *parent_ctx,
                                         const char *tool_name,
                                         bool include_content);

terra_span_t *terra_begin_safety_span_ctx(terra_t *inst,
                                           const terra_span_context_t *parent_ctx,
                                           const char *check_name,
                                           bool include_content);

terra_span_t *terra_begin_streaming_span_ctx(terra_t *inst,
                                              const terra_span_context_t *parent_ctx,
                                              const char *model,
                                              bool include_content);

/* ── Span mutation ─────────────────────────────────────────────────────── */

void terra_span_set_string(terra_span_t *span, const char *key, const char *value);
void terra_span_set_int(terra_span_t *span, const char *key, int64_t value);
void terra_span_set_double(terra_span_t *span, const char *key, double value);
void terra_span_set_bool(terra_span_t *span, const char *key, bool value);
void terra_span_set_status(terra_span_t *span, uint8_t status_code, const char *description);
void terra_span_end(terra_t *inst, terra_span_t *span);

/* ── Events ────────────────────────────────────────────────────────────── */

void terra_span_add_event(terra_span_t *span, const char *name);
void terra_span_add_event_ts(terra_span_t *span, const char *name, uint64_t timestamp_ns);

/* ── Error recording ───────────────────────────────────────────────────── */

void terra_span_record_error(terra_span_t *span,
                              const char *error_type,
                              const char *error_message,
                              bool set_status);

/* ── Streaming ─────────────────────────────────────────────────────────── */

void terra_streaming_record_token(terra_span_t *span);
void terra_streaming_record_first_token(terra_span_t *span);
void terra_streaming_end(terra_span_t *span);

/* ── Context extraction ────────────────────────────────────────────────── */

terra_span_context_t terra_span_context(const terra_span_t *span);

/* ── Diagnostics ───────────────────────────────────────────────────────── */

/**
 * Returns the last error code set on the calling thread.
 */
int terra_last_error(void);

/**
 * Copies the last error message into buf. Returns number of bytes written.
 */
uint32_t terra_last_error_message(char *buf, uint32_t max_len);

/**
 * Returns the total number of spans dropped due to ring buffer overflow.
 */
uint64_t terra_spans_dropped(const terra_t *inst);

/**
 * Returns true if the transport layer is in a degraded state.
 */
bool terra_transport_degraded(const terra_t *inst);

/* ── Version ───────────────────────────────────────────────────────────── */

terra_version_t terra_get_version(void);

/* ── Metrics ───────────────────────────────────────────────────────────── */

void terra_record_inference_duration(terra_t *inst, double duration_ms);
void terra_record_token_count(terra_t *inst, int64_t input_tokens, int64_t output_tokens);

/* ── Test support ──────────────────────────────────────────────────────── */

/**
 * Drain completed spans into out_buf. Returns number of spans written.
 * For testing only.
 */
uint32_t terra_test_drain_spans(terra_t *inst, void *out_buf, uint32_t max);

/**
 * Reset instance state (clear spans, metrics). For testing only.
 */
void terra_test_reset(terra_t *inst);

#ifdef __cplusplus
}
#endif

#endif /* TERRA_H */
