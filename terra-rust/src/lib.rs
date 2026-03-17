//! Safe Rust bindings for the Terra GenAI observability SDK.
//!
//! Terra instruments model inference, embeddings, agent steps, tool calls, and
//! safety checks with OpenTelemetry-compatible tracing.
//!
//! # Quick start
//!
//! ```no_run
//! use terra::{Terra, TerraConfig};
//!
//! let config = TerraConfig::new()
//!     .service_name("my-app")
//!     .service_version("1.0.0")
//!     .otlp_endpoint("http://localhost:4318");
//!
//! let terra = Terra::init_with_config(&config).expect("failed to init Terra");
//!
//! terra.with_inference_span("gpt-4", None, true, |span| {
//!     span.set_string("gen_ai.request.model", "gpt-4");
//!     span.set_int("gen_ai.usage.input_tokens", 128);
//! });
//! ```

pub mod error;
pub mod ffi;

pub use error::{ContentPolicy, LifecycleState, RedactionStrategy, StatusCode, TerraError};

use std::ffi::CString;
use std::marker::PhantomData;
use std::ptr;

/// ABI-stable span context for parent-child linking.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpanContext {
    pub trace_id_hi: u64,
    pub trace_id_lo: u64,
    pub span_id: u64,
}

impl SpanContext {
    fn to_raw(&self) -> ffi::terra_span_context_t {
        ffi::terra_span_context_t {
            trace_id_hi: self.trace_id_hi,
            trace_id_lo: self.trace_id_lo,
            span_id: self.span_id,
        }
    }

    fn from_raw(raw: ffi::terra_span_context_t) -> Self {
        Self {
            trace_id_hi: raw.trace_id_hi,
            trace_id_lo: raw.trace_id_lo,
            span_id: raw.span_id,
        }
    }
}

/// Library version.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

/// Returns the compiled Terra library version.
pub fn get_version() -> Version {
    let v = unsafe { ffi::terra_get_version() };
    Version {
        major: v.major,
        minor: v.minor,
        patch: v.patch,
    }
}

/// Returns the last error code set on the calling thread.
pub fn last_error() -> Option<TerraError> {
    TerraError::from_code(unsafe { ffi::terra_last_error() })
}

/// Returns the last error message from the Zig core.
pub fn last_error_message() -> String {
    let mut buf = vec![0u8; 512];
    let written = unsafe {
        ffi::terra_last_error_message(buf.as_mut_ptr() as *mut _, buf.len() as u32)
    };
    if written == 0 {
        return String::new();
    }
    buf.truncate(written as usize);
    String::from_utf8_lossy(&buf).into_owned()
}

// ── Configuration builder ───────────────────────────────────────────────────

/// Builder for Terra configuration.
///
/// All string fields are owned `CString` values that remain valid for the
/// lifetime of the builder.
pub struct TerraConfig {
    service_name: Option<CString>,
    service_version: Option<CString>,
    otlp_endpoint: Option<CString>,
    hmac_key: Option<CString>,
    max_spans: u32,
    max_attributes_per_span: u16,
    max_events_per_span: u16,
    max_event_attrs: u16,
    batch_size: u32,
    flush_interval_ms: u64,
    content_policy: ContentPolicy,
    redaction_strategy: RedactionStrategy,
    emit_legacy_sha256: bool,
}

impl TerraConfig {
    /// Create a new configuration with default values.
    pub fn new() -> Self {
        Self {
            service_name: None,
            service_version: None,
            otlp_endpoint: None,
            hmac_key: None,
            max_spans: 0,
            max_attributes_per_span: 0,
            max_events_per_span: 0,
            max_event_attrs: 0,
            batch_size: 0,
            flush_interval_ms: 0,
            content_policy: ContentPolicy::Never,
            redaction_strategy: RedactionStrategy::Drop,
            emit_legacy_sha256: false,
        }
    }

    pub fn service_name(mut self, name: &str) -> Self {
        self.service_name = CString::new(name).ok();
        self
    }

    pub fn service_version(mut self, version: &str) -> Self {
        self.service_version = CString::new(version).ok();
        self
    }

    pub fn otlp_endpoint(mut self, endpoint: &str) -> Self {
        self.otlp_endpoint = CString::new(endpoint).ok();
        self
    }

    pub fn hmac_key(mut self, key: &str) -> Self {
        self.hmac_key = CString::new(key).ok();
        self
    }

    pub fn max_spans(mut self, n: u32) -> Self {
        self.max_spans = n;
        self
    }

    pub fn max_attributes_per_span(mut self, n: u16) -> Self {
        self.max_attributes_per_span = n;
        self
    }

    pub fn max_events_per_span(mut self, n: u16) -> Self {
        self.max_events_per_span = n;
        self
    }

    pub fn max_event_attrs(mut self, n: u16) -> Self {
        self.max_event_attrs = n;
        self
    }

    pub fn batch_size(mut self, n: u32) -> Self {
        self.batch_size = n;
        self
    }

    pub fn flush_interval_ms(mut self, ms: u64) -> Self {
        self.flush_interval_ms = ms;
        self
    }

    pub fn content_policy(mut self, policy: ContentPolicy) -> Self {
        self.content_policy = policy;
        self
    }

    pub fn redaction_strategy(mut self, strategy: RedactionStrategy) -> Self {
        self.redaction_strategy = strategy;
        self
    }

    pub fn emit_legacy_sha256(mut self, emit: bool) -> Self {
        self.emit_legacy_sha256 = emit;
        self
    }

    /// Build the raw C config struct. The returned struct borrows from `self`,
    /// so `self` must outlive any use of the raw config.
    fn to_raw(&self) -> ffi::terra_config_t {
        ffi::terra_config_t {
            max_spans: self.max_spans,
            max_attributes_per_span: self.max_attributes_per_span,
            max_events_per_span: self.max_events_per_span,
            max_event_attrs: self.max_event_attrs,
            batch_size: self.batch_size,
            flush_interval_ms: self.flush_interval_ms,
            content_policy: self.content_policy.to_raw(),
            redaction_strategy: self.redaction_strategy.to_raw(),
            hmac_key: self
                .hmac_key
                .as_ref()
                .map_or(ptr::null(), |s| s.as_ptr()),
            emit_legacy_sha256: self.emit_legacy_sha256,
            service_name: self
                .service_name
                .as_ref()
                .map_or(ptr::null(), |s| s.as_ptr()),
            service_version: self
                .service_version
                .as_ref()
                .map_or(ptr::null(), |s| s.as_ptr()),
            otlp_endpoint: self
                .otlp_endpoint
                .as_ref()
                .map_or(ptr::null(), |s| s.as_ptr()),
            clock_fn: None,
            clock_ctx: ptr::null_mut(),
            transport_vtable: ffi::terra_transport_vtable_t {
                send_fn: None,
                flush_fn: None,
                shutdown_fn: None,
                context: ptr::null_mut(),
            },
            scheduler_vtable: ffi::terra_scheduler_vtable_t {
                schedule_fn: None,
                cancel_fn: None,
                context: ptr::null_mut(),
            },
            storage_vtable: ffi::terra_storage_vtable_t {
                write_fn: None,
                read_fn: None,
                discard_oldest_fn: None,
                available_bytes_fn: None,
                context: ptr::null_mut(),
            },
        }
    }
}

impl Default for TerraConfig {
    fn default() -> Self {
        Self::new()
    }
}

// ── Terra instance ──────────────────────────────────────────────────────────

/// A running Terra observability instance.
///
/// Owns the underlying Zig core handle and shuts it down on drop.
/// Not `Send` or `Sync` — the Zig core manages its own thread safety.
pub struct Terra {
    handle: *mut ffi::terra_t,
}

// The Zig core uses internal locks for thread safety.
// The raw pointer is only accessed through the C API which is thread-safe.
unsafe impl Send for Terra {}
unsafe impl Sync for Terra {}

impl Terra {
    /// Initialize Terra with default configuration.
    pub fn init() -> Result<Self, TerraError> {
        let handle = unsafe { ffi::terra_init(ptr::null()) };
        if handle.is_null() {
            Err(last_error().unwrap_or(TerraError::Unknown(-1)))
        } else {
            Ok(Self { handle })
        }
    }

    /// Initialize Terra with the given configuration.
    pub fn init_with_config(config: &TerraConfig) -> Result<Self, TerraError> {
        let raw = config.to_raw();
        let handle = unsafe { ffi::terra_init(&raw) };
        if handle.is_null() {
            Err(last_error().unwrap_or(TerraError::Unknown(-1)))
        } else {
            Ok(Self { handle })
        }
    }

    /// Returns true if the instance is in the running state.
    pub fn is_running(&self) -> bool {
        unsafe { ffi::terra_is_running(self.handle) }
    }

    /// Returns the current lifecycle state.
    pub fn state(&self) -> LifecycleState {
        LifecycleState::from_raw(unsafe { ffi::terra_get_state(self.handle) })
    }

    /// Set the session ID for span enrichment.
    pub fn set_session_id(&self, session_id: &str) -> Result<(), TerraError> {
        let c_id = CString::new(session_id).map_err(|_| TerraError::InvalidConfig)?;
        let rc = unsafe { ffi::terra_set_session_id(self.handle as *mut _, c_id.as_ptr()) };
        match TerraError::from_code(rc) {
            None => Ok(()),
            Some(e) => Err(e),
        }
    }

    /// Set service name and version at runtime.
    pub fn set_service_info(&self, name: &str, version: &str) -> Result<(), TerraError> {
        let c_name = CString::new(name).map_err(|_| TerraError::InvalidConfig)?;
        let c_ver = CString::new(version).map_err(|_| TerraError::InvalidConfig)?;
        let rc = unsafe {
            ffi::terra_set_service_info(self.handle as *mut _, c_name.as_ptr(), c_ver.as_ptr())
        };
        match TerraError::from_code(rc) {
            None => Ok(()),
            Some(e) => Err(e),
        }
    }

    /// Number of spans dropped due to ring buffer overflow.
    pub fn spans_dropped(&self) -> u64 {
        unsafe { ffi::terra_spans_dropped(self.handle) }
    }

    /// Returns true if the transport is in a degraded state.
    pub fn transport_degraded(&self) -> bool {
        unsafe { ffi::terra_transport_degraded(self.handle) }
    }

    /// Record an inference duration metric.
    pub fn record_inference_duration(&self, duration_ms: f64) {
        unsafe { ffi::terra_record_inference_duration(self.handle as *mut _, duration_ms) }
    }

    /// Record input/output token counts.
    pub fn record_token_count(&self, input: i64, output: i64) {
        unsafe { ffi::terra_record_token_count(self.handle as *mut _, input, output) }
    }

    /// Explicitly shut down the instance. Also called on drop.
    pub fn shutdown(&mut self) -> Result<(), TerraError> {
        if self.handle.is_null() {
            return Ok(());
        }
        let rc = unsafe { ffi::terra_shutdown(self.handle) };
        self.handle = ptr::null_mut();
        match TerraError::from_code(rc) {
            None => Ok(()),
            Some(e) => Err(e),
        }
    }

    // ── Span creation ───────────────────────────────────────────────────

    /// Begin an inference span.
    pub fn begin_inference_span(
        &self,
        model: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_model = CString::new(model).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_inference_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_model.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    /// Begin an embedding span.
    pub fn begin_embedding_span(
        &self,
        model: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_model = CString::new(model).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_embedding_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_model.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    /// Begin an agent invocation span.
    pub fn begin_agent_span(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_name = CString::new(name).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_agent_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_name.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    /// Begin a tool execution span.
    pub fn begin_tool_span(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_name = CString::new(name).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_tool_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_name.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    /// Begin a safety check span.
    pub fn begin_safety_span(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_name = CString::new(name).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_safety_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_name.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    /// Begin a streaming inference span.
    pub fn begin_streaming_span(
        &self,
        model: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
    ) -> Option<TerraSpan<'_>> {
        let c_model = CString::new(model).ok()?;
        let parent_raw = parent.map(SpanContext::to_raw);
        let parent_ptr = parent_raw
            .as_ref()
            .map_or(ptr::null(), |p| p as *const _);
        let span = unsafe {
            ffi::terra_begin_streaming_span_ctx(
                self.handle as *mut _,
                parent_ptr,
                c_model.as_ptr(),
                include_content,
            )
        };
        TerraSpan::from_raw(self, span)
    }

    // ── Closure-based span helpers ──────────────────────────────────────

    /// Execute a closure within an inference span, ending the span automatically.
    pub fn with_inference_span<F, R>(
        &self,
        model: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
        f: F,
    ) -> Option<R>
    where
        F: FnOnce(&TerraSpan<'_>) -> R,
    {
        let mut span = self.begin_inference_span(model, parent, include_content)?;
        let result = f(&span);
        span.end();
        Some(result)
    }

    /// Execute a closure within an embedding span.
    pub fn with_embedding_span<F, R>(
        &self,
        model: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
        f: F,
    ) -> Option<R>
    where
        F: FnOnce(&TerraSpan<'_>) -> R,
    {
        let mut span = self.begin_embedding_span(model, parent, include_content)?;
        let result = f(&span);
        span.end();
        Some(result)
    }

    /// Execute a closure within an agent span.
    pub fn with_agent_span<F, R>(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
        f: F,
    ) -> Option<R>
    where
        F: FnOnce(&TerraSpan<'_>) -> R,
    {
        let mut span = self.begin_agent_span(name, parent, include_content)?;
        let result = f(&span);
        span.end();
        Some(result)
    }

    /// Execute a closure within a tool span.
    pub fn with_tool_span<F, R>(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
        f: F,
    ) -> Option<R>
    where
        F: FnOnce(&TerraSpan<'_>) -> R,
    {
        let mut span = self.begin_tool_span(name, parent, include_content)?;
        let result = f(&span);
        span.end();
        Some(result)
    }

    /// Execute a closure within a safety check span.
    pub fn with_safety_span<F, R>(
        &self,
        name: &str,
        parent: Option<&SpanContext>,
        include_content: bool,
        f: F,
    ) -> Option<R>
    where
        F: FnOnce(&TerraSpan<'_>) -> R,
    {
        let mut span = self.begin_safety_span(name, parent, include_content)?;
        let result = f(&span);
        span.end();
        Some(result)
    }
}

impl Drop for Terra {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                ffi::terra_shutdown(self.handle);
            }
            self.handle = ptr::null_mut();
        }
    }
}

// ── Span ────────────────────────────────────────────────────────────────────

/// A live span tied to a `Terra` instance.
///
/// Automatically ended on drop if not ended explicitly.
pub struct TerraSpan<'a> {
    terra: &'a Terra,
    handle: *mut ffi::terra_span_t,
    ended: bool,
    _marker: PhantomData<&'a ()>,
}

impl<'a> TerraSpan<'a> {
    fn from_raw(terra: &'a Terra, handle: *mut ffi::terra_span_t) -> Option<Self> {
        if handle.is_null() {
            None
        } else {
            Some(Self {
                terra,
                handle,
                ended: false,
                _marker: PhantomData,
            })
        }
    }

    /// Set a string attribute on the span.
    pub fn set_string(&self, key: &str, value: &str) {
        if let (Ok(c_key), Ok(c_val)) = (CString::new(key), CString::new(value)) {
            unsafe { ffi::terra_span_set_string(self.handle, c_key.as_ptr(), c_val.as_ptr()) }
        }
    }

    /// Set an integer attribute on the span.
    pub fn set_int(&self, key: &str, value: i64) {
        if let Ok(c_key) = CString::new(key) {
            unsafe { ffi::terra_span_set_int(self.handle, c_key.as_ptr(), value) }
        }
    }

    /// Set a floating-point attribute on the span.
    pub fn set_double(&self, key: &str, value: f64) {
        if let Ok(c_key) = CString::new(key) {
            unsafe { ffi::terra_span_set_double(self.handle, c_key.as_ptr(), value) }
        }
    }

    /// Set a boolean attribute on the span.
    pub fn set_bool(&self, key: &str, value: bool) {
        if let Ok(c_key) = CString::new(key) {
            unsafe { ffi::terra_span_set_bool(self.handle, c_key.as_ptr(), value) }
        }
    }

    /// Set the span status.
    pub fn set_status(&self, code: StatusCode, description: &str) {
        if let Ok(c_desc) = CString::new(description) {
            unsafe {
                ffi::terra_span_set_status(self.handle, code.to_raw(), c_desc.as_ptr())
            }
        }
    }

    /// Add a named event to the span.
    pub fn add_event(&self, name: &str) {
        if let Ok(c_name) = CString::new(name) {
            unsafe { ffi::terra_span_add_event(self.handle, c_name.as_ptr()) }
        }
    }

    /// Add a named event with an explicit timestamp (nanoseconds since epoch).
    pub fn add_event_ts(&self, name: &str, timestamp_ns: u64) {
        if let Ok(c_name) = CString::new(name) {
            unsafe { ffi::terra_span_add_event_ts(self.handle, c_name.as_ptr(), timestamp_ns) }
        }
    }

    /// Record an error on the span.
    pub fn record_error(&self, error_type: &str, message: &str, set_status: bool) {
        if let (Ok(c_type), Ok(c_msg)) = (CString::new(error_type), CString::new(message)) {
            unsafe {
                ffi::terra_span_record_error(
                    self.handle,
                    c_type.as_ptr(),
                    c_msg.as_ptr(),
                    set_status,
                )
            }
        }
    }

    /// Record a streaming token event.
    pub fn streaming_record_token(&self) {
        unsafe { ffi::terra_streaming_record_token(self.handle) }
    }

    /// Record the first token event (TTFT measurement).
    pub fn streaming_record_first_token(&self) {
        unsafe { ffi::terra_streaming_record_first_token(self.handle) }
    }

    /// End streaming on this span.
    pub fn streaming_end(&self) {
        unsafe { ffi::terra_streaming_end(self.handle) }
    }

    /// Extract the span context for parent-child linking.
    pub fn context(&self) -> SpanContext {
        SpanContext::from_raw(unsafe { ffi::terra_span_context(self.handle) })
    }

    /// End the span. Called automatically on drop if not called explicitly.
    pub fn end(&mut self) {
        if !self.ended {
            self.ended = true;
            unsafe { ffi::terra_span_end(self.terra.handle as *mut _, self.handle) }
        }
    }
}

impl Drop for TerraSpan<'_> {
    fn drop(&mut self) {
        if !self.ended {
            self.end();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn span_context_round_trip() {
        let ctx = SpanContext {
            trace_id_hi: 0xDEAD_BEEF_CAFE_BABE,
            trace_id_lo: 0x0123_4567_89AB_CDEF,
            span_id: 0xFEED_FACE_1234_5678,
        };
        let raw = ctx.to_raw();
        let back = SpanContext::from_raw(raw);
        assert_eq!(ctx, back);
    }

    #[test]
    fn error_from_code() {
        assert_eq!(TerraError::from_code(0), None);
        assert_eq!(
            TerraError::from_code(1),
            Some(TerraError::AlreadyInitialized)
        );
        assert_eq!(
            TerraError::from_code(6),
            Some(TerraError::ShuttingDown)
        );
        assert_eq!(
            TerraError::from_code(99),
            Some(TerraError::Unknown(99))
        );
    }

    #[test]
    fn config_builder() {
        let config = TerraConfig::new()
            .service_name("test-svc")
            .service_version("0.1.0")
            .max_spans(1024)
            .content_policy(ContentPolicy::OptIn)
            .redaction_strategy(RedactionStrategy::HmacSha256)
            .hmac_key("secret");

        let raw = config.to_raw();
        assert_eq!(raw.max_spans, 1024);
        assert_eq!(raw.content_policy, ffi::TERRA_CONTENT_OPT_IN);
        assert_eq!(raw.redaction_strategy, ffi::TERRA_REDACT_HMAC_SHA256);
        assert!(!raw.service_name.is_null());
        let name = unsafe { std::ffi::CStr::from_ptr(raw.service_name) };
        assert_eq!(name.to_str().unwrap(), "test-svc");
    }

    #[test]
    fn lifecycle_state_display() {
        assert_eq!(LifecycleState::Running.to_string(), "running");
        assert_eq!(LifecycleState::ShuttingDown.to_string(), "shutting down");
    }

    #[test]
    fn version_struct() {
        let v = Version {
            major: 1,
            minor: 0,
            patch: 0,
        };
        assert_eq!(v.major, 1);
    }
}
