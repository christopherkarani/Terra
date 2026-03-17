//! Raw C FFI bindings for Terra Zig Core.
//!
//! Hand-written declarations matching `zig-core/include/terra.h` exactly.
//! All types and functions are `pub` for use by the safe wrapper in `lib.rs`.

#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_void};

// ── Opaque handles ──────────────────────────────────────────────────────────

pub enum terra_s {}
pub type terra_t = terra_s;

pub enum terra_span_s {}
pub type terra_span_t = terra_span_s;

pub enum terra_scope_s {}
pub type terra_scope_t = terra_scope_s;

// ── Error codes ─────────────────────────────────────────────────────────────

pub const TERRA_OK: c_int = 0;
pub const TERRA_ERR_ALREADY_INITIALIZED: c_int = 1;
pub const TERRA_ERR_NOT_INITIALIZED: c_int = 2;
pub const TERRA_ERR_INVALID_CONFIG: c_int = 3;
pub const TERRA_ERR_OUT_OF_MEMORY: c_int = 4;
pub const TERRA_ERR_TRANSPORT_FAILED: c_int = 5;
pub const TERRA_ERR_SHUTTING_DOWN: c_int = 6;

// ── Lifecycle state ─────────────────────────────────────────────────────────

pub const TERRA_STATE_STOPPED: u8 = 0;
pub const TERRA_STATE_STARTING: u8 = 1;
pub const TERRA_STATE_RUNNING: u8 = 2;
pub const TERRA_STATE_SHUTTING_DOWN: u8 = 3;

// ── Content policy ──────────────────────────────────────────────────────────

pub const TERRA_CONTENT_NEVER: c_int = 0;
pub const TERRA_CONTENT_OPT_IN: c_int = 1;
pub const TERRA_CONTENT_ALWAYS: c_int = 2;

// ── Redaction strategy ──────────────────────────────────────────────────────

pub const TERRA_REDACT_DROP: c_int = 0;
pub const TERRA_REDACT_LENGTH_ONLY: c_int = 1;
pub const TERRA_REDACT_HMAC_SHA256: c_int = 2;

// ── Status code ─────────────────────────────────────────────────────────────

pub const TERRA_STATUS_UNSET: u8 = 0;
pub const TERRA_STATUS_OK: u8 = 1;
pub const TERRA_STATUS_ERROR: u8 = 2;

// ── Span context (flat, ABI-stable) ─────────────────────────────────────────

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct terra_span_context_t {
    pub trace_id_hi: u64,
    pub trace_id_lo: u64,
    pub span_id: u64,
}

// ── Version ─────────────────────────────────────────────────────────────────

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct terra_version_t {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

// ── Transport VTable ────────────────────────────────────────────────────────

pub type terra_send_fn = Option<unsafe extern "C" fn(data: *const u8, len: u32, ctx: *mut c_void) -> c_int>;
pub type terra_flush_fn = Option<unsafe extern "C" fn(ctx: *mut c_void)>;
pub type terra_shutdown_fn = Option<unsafe extern "C" fn(ctx: *mut c_void)>;

#[repr(C)]
pub struct terra_transport_vtable_t {
    pub send_fn: terra_send_fn,
    pub flush_fn: terra_flush_fn,
    pub shutdown_fn: terra_shutdown_fn,
    pub context: *mut c_void,
}

// ── Scheduler VTable ────────────────────────────────────────────────────────

pub type terra_scheduler_callback_fn = Option<unsafe extern "C" fn(ctx: *mut c_void)>;
pub type terra_schedule_fn = Option<
    unsafe extern "C" fn(
        callback: terra_scheduler_callback_fn,
        interval_ms: u64,
        cb_ctx: *mut c_void,
        ctx: *mut c_void,
    ) -> u64,
>;
pub type terra_cancel_fn = Option<unsafe extern "C" fn(handle: u64, ctx: *mut c_void)>;

#[repr(C)]
pub struct terra_scheduler_vtable_t {
    pub schedule_fn: terra_schedule_fn,
    pub cancel_fn: terra_cancel_fn,
    pub context: *mut c_void,
}

// ── Storage VTable ──────────────────────────────────────────────────────────

pub type terra_storage_write_fn =
    Option<unsafe extern "C" fn(data: *const u8, len: u32, ctx: *mut c_void) -> c_int>;
pub type terra_storage_read_fn =
    Option<unsafe extern "C" fn(buf: *mut u8, max_len: u32, ctx: *mut c_void) -> u32>;
pub type terra_storage_discard_oldest_fn =
    Option<unsafe extern "C" fn(bytes: u32, ctx: *mut c_void)>;
pub type terra_storage_available_bytes_fn =
    Option<unsafe extern "C" fn(ctx: *mut c_void) -> u64>;

#[repr(C)]
pub struct terra_storage_vtable_t {
    pub write_fn: terra_storage_write_fn,
    pub read_fn: terra_storage_read_fn,
    pub discard_oldest_fn: terra_storage_discard_oldest_fn,
    pub available_bytes_fn: terra_storage_available_bytes_fn,
    pub context: *mut c_void,
}

// ── Clock function ──────────────────────────────────────────────────────────

pub type terra_clock_fn = Option<unsafe extern "C" fn(ctx: *mut c_void) -> u64>;

// ── Configuration ───────────────────────────────────────────────────────────

#[repr(C)]
pub struct terra_config_t {
    pub max_spans: u32,
    pub max_attributes_per_span: u16,
    pub max_events_per_span: u16,
    pub max_event_attrs: u16,
    pub batch_size: u32,
    pub flush_interval_ms: u64,
    pub content_policy: c_int,
    pub redaction_strategy: c_int,
    pub hmac_key: *const c_char,
    pub emit_legacy_sha256: bool,
    pub service_name: *const c_char,
    pub service_version: *const c_char,
    pub otlp_endpoint: *const c_char,
    pub clock_fn: terra_clock_fn,
    pub clock_ctx: *mut c_void,
    pub transport_vtable: terra_transport_vtable_t,
    pub scheduler_vtable: terra_scheduler_vtable_t,
    pub storage_vtable: terra_storage_vtable_t,
}

// ── Extern declarations ─────────────────────────────────────────────────────

extern "C" {
    // Lifecycle
    pub fn terra_init(config: *const terra_config_t) -> *mut terra_t;
    pub fn terra_shutdown(inst: *mut terra_t) -> c_int;
    pub fn terra_get_state(inst: *const terra_t) -> u8;
    pub fn terra_is_running(inst: *const terra_t) -> bool;

    // Runtime configuration
    pub fn terra_set_session_id(inst: *mut terra_t, session_id: *const c_char) -> c_int;
    pub fn terra_set_service_info(
        inst: *mut terra_t,
        name: *const c_char,
        version: *const c_char,
    ) -> c_int;

    // Span creation (parent by context)
    pub fn terra_begin_inference_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        model: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    pub fn terra_begin_embedding_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        model: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    pub fn terra_begin_agent_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        agent_name: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    pub fn terra_begin_tool_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        tool_name: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    pub fn terra_begin_safety_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        check_name: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    pub fn terra_begin_streaming_span_ctx(
        inst: *mut terra_t,
        parent_ctx: *const terra_span_context_t,
        model: *const c_char,
        include_content: bool,
    ) -> *mut terra_span_t;

    // Span mutation
    pub fn terra_span_set_string(span: *mut terra_span_t, key: *const c_char, value: *const c_char);
    pub fn terra_span_set_int(span: *mut terra_span_t, key: *const c_char, value: i64);
    pub fn terra_span_set_double(span: *mut terra_span_t, key: *const c_char, value: f64);
    pub fn terra_span_set_bool(span: *mut terra_span_t, key: *const c_char, value: bool);
    pub fn terra_span_set_status(span: *mut terra_span_t, status_code: u8, description: *const c_char);
    pub fn terra_span_end(inst: *mut terra_t, span: *mut terra_span_t);

    // Events
    pub fn terra_span_add_event(span: *mut terra_span_t, name: *const c_char);
    pub fn terra_span_add_event_ts(span: *mut terra_span_t, name: *const c_char, timestamp_ns: u64);

    // Error recording
    pub fn terra_span_record_error(
        span: *mut terra_span_t,
        error_type: *const c_char,
        error_message: *const c_char,
        set_status: bool,
    );

    // Streaming
    pub fn terra_streaming_record_token(span: *mut terra_span_t);
    pub fn terra_streaming_record_first_token(span: *mut terra_span_t);
    pub fn terra_streaming_end(span: *mut terra_span_t);

    // Context extraction
    pub fn terra_span_context(span: *const terra_span_t) -> terra_span_context_t;

    // Diagnostics
    pub fn terra_last_error() -> c_int;
    pub fn terra_last_error_message(buf: *mut c_char, max_len: u32) -> u32;
    pub fn terra_spans_dropped(inst: *const terra_t) -> u64;
    pub fn terra_transport_degraded(inst: *const terra_t) -> bool;

    // Version
    pub fn terra_get_version() -> terra_version_t;

    // Metrics
    pub fn terra_record_inference_duration(inst: *mut terra_t, duration_ms: f64);
    pub fn terra_record_token_count(inst: *mut terra_t, input_tokens: i64, output_tokens: i64);

    // Test support
    pub fn terra_test_drain_spans(inst: *mut terra_t, out_buf: *mut c_void, max: u32) -> u32;
    pub fn terra_test_reset(inst: *mut terra_t);
}
