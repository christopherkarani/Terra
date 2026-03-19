#include "terra_ros2_bridge_core.hpp"

#include <chrono>
#include <curl/curl.h>
#include <mutex>
#include <sstream>
#include <utility>

namespace terra_ros2 {

namespace {

std::string build_traces_url(std::string endpoint) {
    while (!endpoint.empty() && endpoint.back() == '/') {
        endpoint.pop_back();
    }

    const std::string suffix = "/v1/traces";
    if (endpoint.size() >= suffix.size() &&
        endpoint.compare(endpoint.size() - suffix.size(), suffix.size(), suffix) == 0) {
        return endpoint;
    }

    return endpoint + suffix;
}

bool ensure_curl_initialized(std::string *error) {
    static std::once_flag once;
    static CURLcode init_result = CURLE_OK;

    std::call_once(once, [] {
        init_result = curl_global_init(CURL_GLOBAL_DEFAULT);
    });

    if (init_result != CURLE_OK) {
        if (error != nullptr) {
            *error = curl_easy_strerror(init_result);
        }
        return false;
    }

    return true;
}

}  // namespace

CurlTraceForwarder::CurlTraceForwarder(std::string endpoint)
    : traces_url_(build_traces_url(std::move(endpoint))) {}

bool CurlTraceForwarder::post_traces(const uint8_t *data, std::size_t size, std::string *error) {
    if (data == nullptr || size == 0) {
        if (error != nullptr) {
            *error = "empty OTLP trace payload";
        }
        return false;
    }

    if (!ensure_curl_initialized(error)) {
        return false;
    }

    CURL *curl = curl_easy_init();
    if (curl == nullptr) {
        if (error != nullptr) {
            *error = "curl_easy_init failed";
        }
        return false;
    }

    struct curl_slist *headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/x-protobuf");

    curl_easy_setopt(curl, CURLOPT_URL, traces_url_.c_str());
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, reinterpret_cast<const char *>(data));
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(size));
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 5000L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 15000L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

    const CURLcode perform_result = curl_easy_perform(curl);
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (perform_result != CURLE_OK) {
        if (error != nullptr) {
            *error = curl_easy_strerror(perform_result);
        }
        return false;
    }

    if (http_code < 200 || http_code >= 300) {
        if (error != nullptr) {
            *error = "collector returned HTTP " + std::to_string(http_code);
        }
        return false;
    }

    return true;
}

TerraRos2BridgeCore::TerraRos2BridgeCore(
    terra_t *terra,
    std::shared_ptr<TraceForwarder> forwarder)
    : terra_(terra), forwarder_(std::move(forwarder)) {}

bool TerraRos2BridgeCore::ingest_trace_batch(const uint8_t *data, std::size_t size) {
    payloads_received_.fetch_add(1, std::memory_order_relaxed);

    const auto start = std::chrono::steady_clock::now();
    std::string error;

    bool success = false;
    if (data == nullptr || size == 0) {
        error = "empty OTLP trace payload";
    } else if (!forwarder_) {
        error = "trace forwarder is not configured";
    } else {
        success = forwarder_->post_traces(data, size, &error);
    }

    const auto end = std::chrono::steady_clock::now();
    const double duration_ms =
        std::chrono::duration_cast<std::chrono::duration<double, std::milli>>(end - start).count();

    if (success) {
        payloads_forwarded_.fetch_add(1, std::memory_order_relaxed);
        bytes_forwarded_.fetch_add(static_cast<uint64_t>(size), std::memory_order_relaxed);
        set_last_error("");
    } else {
        payloads_failed_.fetch_add(1, std::memory_order_relaxed);
        set_last_error(error);
    }

    record_forward_span(size, success, duration_ms, success ? nullptr : &error);
    return success;
}

BridgeMetrics TerraRos2BridgeCore::snapshot_metrics() const {
    BridgeMetrics metrics;
    metrics.payloads_received = payloads_received_.load(std::memory_order_relaxed);
    metrics.payloads_forwarded = payloads_forwarded_.load(std::memory_order_relaxed);
    metrics.payloads_failed = payloads_failed_.load(std::memory_order_relaxed);
    metrics.bytes_forwarded = bytes_forwarded_.load(std::memory_order_relaxed);
    metrics.spans_dropped = terra_ ? terra_spans_dropped(terra_) : 0;
    metrics.transport_degraded = terra_ ? terra_transport_degraded(terra_) : false;
    metrics.lifecycle_state = terra_ ? terra_get_state(terra_) : TERRA_STATE_STOPPED;

    std::lock_guard<std::mutex> lock(error_mutex_);
    metrics.last_error = last_error_;
    return metrics;
}

std::string TerraRos2BridgeCore::metrics_json() const {
    const BridgeMetrics metrics = snapshot_metrics();

    std::ostringstream stream;
    stream << "{"
           << "\"payloads_received\":" << metrics.payloads_received << ","
           << "\"payloads_forwarded\":" << metrics.payloads_forwarded << ","
           << "\"payloads_failed\":" << metrics.payloads_failed << ","
           << "\"bytes_forwarded\":" << metrics.bytes_forwarded << ","
           << "\"spans_dropped\":" << metrics.spans_dropped << ","
           << "\"transport_degraded\":" << (metrics.transport_degraded ? "true" : "false") << ","
           << "\"lifecycle_state\":" << static_cast<unsigned int>(metrics.lifecycle_state) << ","
           << "\"last_error\":\"" << json_escape(metrics.last_error) << "\""
           << "}";
    return stream.str();
}

void TerraRos2BridgeCore::set_last_error(const std::string &message) {
    std::lock_guard<std::mutex> lock(error_mutex_);
    last_error_ = message;
}

void TerraRos2BridgeCore::record_forward_span(
    std::size_t size,
    bool success,
    double duration_ms,
    const std::string *error) {
    if (terra_ == nullptr) {
        return;
    }

    terra_span_t *span = terra_begin_tool_span_ctx(terra_, nullptr, "ros2.otlp.forward", false);
    if (span == nullptr) {
        return;
    }

    terra_span_set_string(span, "terra.ros2.component", "otlp-forwarder");
    terra_span_set_int(span, "terra.ros2.payload_bytes", static_cast<int64_t>(size));
    terra_span_set_double(span, "terra.ros2.forward.duration_ms", duration_ms);
    terra_span_set_bool(span, "terra.ros2.forward.success", success);

    if (success) {
        terra_span_set_status(span, TERRA_STATUS_OK, "forwarded");
    } else if (error != nullptr) {
        terra_span_record_error(span, "TransportError", error->c_str(), true);
    } else {
        terra_span_set_status(span, TERRA_STATUS_ERROR, "forward failed");
    }

    terra_span_end(terra_, span);
}

std::string TerraRos2BridgeCore::json_escape(const std::string &value) {
    std::ostringstream stream;
    for (const char ch : value) {
        switch (ch) {
            case '\\':
                stream << "\\\\";
                break;
            case '"':
                stream << "\\\"";
                break;
            case '\n':
                stream << "\\n";
                break;
            case '\r':
                stream << "\\r";
                break;
            case '\t':
                stream << "\\t";
                break;
            default:
                stream << ch;
                break;
        }
    }
    return stream.str();
}

}  // namespace terra_ros2
