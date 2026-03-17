/*
 * terra.hpp — Modern C++17 header-only SDK for Terra Zig Core
 *
 * RAII wrappers around the terra.h C ABI. Thread-safe by delegation
 * to the underlying C library. Non-copyable, moveable handle types.
 *
 * Usage:
 *   auto inst = terra::Instance::init();
 *   {
 *       auto span = inst.begin_inference("gpt-4");
 *       span.set("gen_ai.request.max_tokens", 1024);
 *       // span ended automatically by destructor
 *   }
 *   inst.shutdown();
 */

#ifndef TERRA_HPP
#define TERRA_HPP

#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

extern "C" {
#include "terra.h"
}

namespace terra {

// ── Enums ──────────────────────────────────────────────────────────────────────

enum class StatusCode : uint8_t {
    Unset = TERRA_STATUS_UNSET,
    Ok    = TERRA_STATUS_OK,
    Error = TERRA_STATUS_ERROR,
};

enum class ContentPolicy : uint8_t {
    Never  = TERRA_CONTENT_NEVER,
    OptIn  = TERRA_CONTENT_OPT_IN,
    Always = TERRA_CONTENT_ALWAYS,
};

enum class RedactionStrategy : uint8_t {
    Drop        = TERRA_REDACT_DROP,
    LengthOnly  = TERRA_REDACT_LENGTH_ONLY,
    HmacSha256  = TERRA_REDACT_HMAC_SHA256,
};

enum class LifecycleState : uint8_t {
    Stopped      = TERRA_STATE_STOPPED,
    Starting     = TERRA_STATE_STARTING,
    Running      = TERRA_STATE_RUNNING,
    ShuttingDown = TERRA_STATE_SHUTTING_DOWN,
};

// ── Error ──────────────────────────────────────────────────────────────────────

class Error : public std::runtime_error {
public:
    explicit Error(int code, const std::string& message)
        : std::runtime_error(message), code_(code) {}

    int code() const noexcept { return code_; }

    /// Build an Error from the thread-local terra_last_error state.
    static Error from_last() {
        int ec = terra_last_error();
        char buf[256];
        uint32_t len = terra_last_error_message(buf, sizeof(buf));
        std::string msg(buf, len);
        if (msg.empty()) {
            msg = "terra error " + std::to_string(ec);
        }
        return Error(ec, msg);
    }

private:
    int code_;
};

// ── SpanContext ────────────────────────────────────────────────────────────────

struct SpanContext {
    uint64_t trace_id_hi = 0;
    uint64_t trace_id_lo = 0;
    uint64_t span_id     = 0;

    bool is_valid() const noexcept {
        return (trace_id_hi | trace_id_lo) != 0 && span_id != 0;
    }

    /// Convert to C ABI struct.
    terra_span_context_t to_c() const noexcept {
        return {trace_id_hi, trace_id_lo, span_id};
    }

    /// Construct from C ABI struct.
    static SpanContext from_c(const terra_span_context_t& c) noexcept {
        return {c.trace_id_hi, c.trace_id_lo, c.span_id};
    }
};

// ── Internal helpers ──────────────────────────────────────────────────────────

namespace detail {

/// Ensure a string_view is null-terminated for the C ABI.
/// If it already ends at a '\0' in memory, return the pointer directly.
/// Otherwise copy into the provided std::string and return its c_str().
inline const char* ensure_z(std::string_view sv, std::string& buf) {
    // Most literals and std::string-backed views are already null-terminated.
    if (!sv.empty() && sv.data()[sv.size()] == '\0') {
        return sv.data();
    }
    buf.assign(sv.data(), sv.size());
    return buf.c_str();
}

} // namespace detail

// ── Forward declarations ──────────────────────────────────────────────────────

class Instance;
class Span;
class StreamingSpan;

// ── Span ──────────────────────────────────────────────────────────────────────

class Span {
    friend class Instance;

public:
    Span() noexcept : inst_(nullptr), span_(nullptr) {}

    ~Span() { end(); }

    // Non-copyable
    Span(const Span&) = delete;
    Span& operator=(const Span&) = delete;

    // Moveable
    Span(Span&& other) noexcept
        : inst_(other.inst_), span_(other.span_) {
        other.inst_ = nullptr;
        other.span_ = nullptr;
    }

    Span& operator=(Span&& other) noexcept {
        if (this != &other) {
            end();
            inst_ = other.inst_;
            span_ = other.span_;
            other.inst_ = nullptr;
            other.span_ = nullptr;
        }
        return *this;
    }

    /// True if this Span owns a live handle.
    explicit operator bool() const noexcept { return span_ != nullptr; }

    // ── Attribute setters ──────────────────────────────────────────────────

    void set(std::string_view key, std::string_view value) {
        if (!span_) return;
        std::string kbuf, vbuf;
        terra_span_set_string(span_,
                              detail::ensure_z(key, kbuf),
                              detail::ensure_z(value, vbuf));
    }

    void set(std::string_view key, int64_t value) {
        if (!span_) return;
        std::string kbuf;
        terra_span_set_int(span_, detail::ensure_z(key, kbuf), value);
    }

    void set(std::string_view key, double value) {
        if (!span_) return;
        std::string kbuf;
        terra_span_set_double(span_, detail::ensure_z(key, kbuf), value);
    }

    void set(std::string_view key, bool value) {
        if (!span_) return;
        std::string kbuf;
        terra_span_set_bool(span_, detail::ensure_z(key, kbuf), value);
    }

    // Convenience: allow plain int to resolve to int64_t, not bool.
    void set(std::string_view key, int value) {
        set(key, static_cast<int64_t>(value));
    }

    // ── Status ─────────────────────────────────────────────────────────────

    void set_status(StatusCode code, std::string_view desc = "") {
        if (!span_) return;
        std::string dbuf;
        terra_span_set_status(span_,
                              static_cast<uint8_t>(code),
                              detail::ensure_z(desc, dbuf));
    }

    // ── Events ─────────────────────────────────────────────────────────────

    void add_event(std::string_view name) {
        if (!span_) return;
        std::string nbuf;
        terra_span_add_event(span_, detail::ensure_z(name, nbuf));
    }

    void add_event(std::string_view name, uint64_t timestamp_ns) {
        if (!span_) return;
        std::string nbuf;
        terra_span_add_event_ts(span_, detail::ensure_z(name, nbuf), timestamp_ns);
    }

    // ── Error recording ────────────────────────────────────────────────────

    void record_error(std::string_view type,
                      std::string_view msg,
                      bool set_status = true) {
        if (!span_) return;
        std::string tbuf, mbuf;
        terra_span_record_error(span_,
                                detail::ensure_z(type, tbuf),
                                detail::ensure_z(msg, mbuf),
                                set_status);
    }

    // ── Context ────────────────────────────────────────────────────────────

    SpanContext context() const {
        if (!span_) return {};
        return SpanContext::from_c(terra_span_context(span_));
    }

    // ── End ────────────────────────────────────────────────────────────────

    /// End the span. Idempotent — safe to call multiple times.
    void end() noexcept {
        if (span_ && inst_) {
            terra_span_end(inst_, span_);
            span_ = nullptr;
        }
    }

protected:
    Span(terra_t* inst, terra_span_t* span) noexcept
        : inst_(inst), span_(span) {}

    terra_t*      inst_;
    terra_span_t* span_;
};

// ── StreamingSpan ─────────────────────────────────────────────────────────────

class StreamingSpan : public Span {
    friend class Instance;

public:
    StreamingSpan() noexcept : Span() {}

    // Moveable (inherits non-copyable from Span)
    StreamingSpan(StreamingSpan&& other) noexcept : Span(std::move(other)) {}

    StreamingSpan& operator=(StreamingSpan&& other) noexcept {
        Span::operator=(std::move(other));
        return *this;
    }

    /// Record a single output token.
    void record_token() {
        if (!span_) return;
        terra_streaming_record_token(span_);
    }

    /// Record time-to-first-token.
    void record_first_token() {
        if (!span_) return;
        terra_streaming_record_first_token(span_);
    }

    /// Finish the streaming span (records final metrics).
    /// The span is then ended normally via destructor or end().
    void finish_stream() {
        if (!span_) return;
        terra_streaming_end(span_);
    }

private:
    StreamingSpan(terra_t* inst, terra_span_t* span) noexcept
        : Span(inst, span) {}
};

// ── Instance ──────────────────────────────────────────────────────────────────

class Instance {
public:
    /// Create a Terra instance with default configuration.
    /// Throws terra::Error on failure.
    static Instance init() {
        terra_t* raw = terra_init(nullptr);
        if (!raw) {
            throw Error::from_last();
        }
        return Instance(raw);
    }

    /// Create a Terra instance with explicit configuration.
    /// Throws terra::Error on failure.
    static Instance init(const terra_config_t& config) {
        terra_t* raw = terra_init(&config);
        if (!raw) {
            throw Error::from_last();
        }
        return Instance(raw);
    }

    ~Instance() { shutdown(); }

    // Non-copyable
    Instance(const Instance&) = delete;
    Instance& operator=(const Instance&) = delete;

    // Moveable
    Instance(Instance&& other) noexcept : inst_(other.inst_) {
        other.inst_ = nullptr;
    }

    Instance& operator=(Instance&& other) noexcept {
        if (this != &other) {
            shutdown();
            inst_ = other.inst_;
            other.inst_ = nullptr;
        }
        return *this;
    }

    /// True if this Instance owns a live handle.
    explicit operator bool() const noexcept { return inst_ != nullptr; }

    /// Get the raw C handle (escape hatch).
    terra_t* raw() const noexcept { return inst_; }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    /// Shut down the instance. Idempotent.
    void shutdown() noexcept {
        if (inst_) {
            terra_shutdown(inst_);
            inst_ = nullptr;
        }
    }

    bool is_running() const noexcept {
        return inst_ ? terra_is_running(inst_) : false;
    }

    LifecycleState state() const noexcept {
        return inst_ ? static_cast<LifecycleState>(terra_get_state(inst_))
                     : LifecycleState::Stopped;
    }

    // ── Configuration (runtime) ────────────────────────────────────────────

    void set_session_id(std::string_view session_id) {
        check_live();
        std::string buf;
        int rc = terra_set_session_id(inst_, detail::ensure_z(session_id, buf));
        if (rc != TERRA_OK) throw Error::from_last();
    }

    void set_service_info(std::string_view name, std::string_view version) {
        check_live();
        std::string nbuf, vbuf;
        int rc = terra_set_service_info(inst_,
                                        detail::ensure_z(name, nbuf),
                                        detail::ensure_z(version, vbuf));
        if (rc != TERRA_OK) throw Error::from_last();
    }

    // ── Span creation ──────────────────────────────────────────────────────

    Span begin_inference(std::string_view model,
                         const SpanContext* parent_ctx = nullptr,
                         bool include_content = false) {
        return begin_span(&terra_begin_inference_span_ctx,
                          model, parent_ctx, include_content);
    }

    Span begin_embedding(std::string_view model,
                         const SpanContext* parent_ctx = nullptr,
                         bool include_content = false) {
        return begin_span(&terra_begin_embedding_span_ctx,
                          model, parent_ctx, include_content);
    }

    Span begin_agent(std::string_view name,
                     const SpanContext* parent_ctx = nullptr,
                     bool include_content = false) {
        return begin_span(&terra_begin_agent_span_ctx,
                          name, parent_ctx, include_content);
    }

    Span begin_tool(std::string_view name,
                    const SpanContext* parent_ctx = nullptr,
                    bool include_content = false) {
        return begin_span(&terra_begin_tool_span_ctx,
                          name, parent_ctx, include_content);
    }

    Span begin_safety(std::string_view name,
                      const SpanContext* parent_ctx = nullptr,
                      bool include_content = false) {
        return begin_span(&terra_begin_safety_span_ctx,
                          name, parent_ctx, include_content);
    }

    StreamingSpan begin_streaming(std::string_view model,
                                  const SpanContext* parent_ctx = nullptr,
                                  bool include_content = false) {
        check_live();
        std::string mbuf;
        terra_span_context_t c_ctx{};
        const terra_span_context_t* ctx_ptr = nullptr;
        if (parent_ctx) {
            c_ctx = parent_ctx->to_c();
            ctx_ptr = &c_ctx;
        }
        terra_span_t* raw = terra_begin_streaming_span_ctx(
            inst_, ctx_ptr, detail::ensure_z(model, mbuf), include_content);
        if (!raw) throw Error::from_last();
        return StreamingSpan(inst_, raw);
    }

    // ── Diagnostics ────────────────────────────────────────────────────────

    uint64_t spans_dropped() const noexcept {
        return inst_ ? terra_spans_dropped(inst_) : 0;
    }

    bool transport_degraded() const noexcept {
        return inst_ ? terra_transport_degraded(inst_) : true;
    }

    // ── Metrics ────────────────────────────────────────────────────────────

    void record_inference_duration(double duration_ms) {
        if (inst_) terra_record_inference_duration(inst_, duration_ms);
    }

    void record_token_count(int64_t input_tokens, int64_t output_tokens) {
        if (inst_) terra_record_token_count(inst_, input_tokens, output_tokens);
    }

    // ── Version ────────────────────────────────────────────────────────────

    static terra_version_t version() noexcept {
        return terra_get_version();
    }

private:
    explicit Instance(terra_t* inst) noexcept : inst_(inst) {}

    void check_live() const {
        if (!inst_) {
            throw Error(TERRA_ERR_NOT_INITIALIZED,
                        "terra instance not initialized or already shut down");
        }
    }

    using SpanCreateFn = terra_span_t* (*)(terra_t*,
                                           const terra_span_context_t*,
                                           const char*,
                                           bool);

    Span begin_span(SpanCreateFn fn,
                    std::string_view name,
                    const SpanContext* parent_ctx,
                    bool include_content) {
        check_live();
        std::string nbuf;
        terra_span_context_t c_ctx{};
        const terra_span_context_t* ctx_ptr = nullptr;
        if (parent_ctx) {
            c_ctx = parent_ctx->to_c();
            ctx_ptr = &c_ctx;
        }
        terra_span_t* raw = fn(inst_, ctx_ptr,
                               detail::ensure_z(name, nbuf),
                               include_content);
        if (!raw) throw Error::from_last();
        return Span(inst_, raw);
    }

    terra_t* inst_;
};

} // namespace terra

#endif // TERRA_HPP
