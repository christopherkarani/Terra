#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

extern "C" {
#include "terra.h"
}

namespace terra_ros2 {

class TraceForwarder {
public:
    virtual ~TraceForwarder() = default;
    virtual bool post_traces(const uint8_t *data, std::size_t size, std::string *error) = 0;
};

class CurlTraceForwarder final : public TraceForwarder {
public:
    explicit CurlTraceForwarder(std::string endpoint);
    bool post_traces(const uint8_t *data, std::size_t size, std::string *error) override;

private:
    std::string traces_url_;
};

struct BridgeMetrics {
    uint64_t payloads_received = 0;
    uint64_t payloads_forwarded = 0;
    uint64_t payloads_failed = 0;
    uint64_t bytes_forwarded = 0;
    uint64_t spans_dropped = 0;
    bool transport_degraded = false;
    uint8_t lifecycle_state = TERRA_STATE_STOPPED;
    std::string last_error;
};

struct BridgeMetadata {
    std::string robot_id;
    std::string vehicle_id;
    std::string mission_id;
    std::string component_name = "terra_ros2_node";
    std::string autonomy_phase;
    std::string content_policy = "never";
    std::string redaction_strategy = "hmac_sha256";
    std::string transport_protocol = "otlp_http";
};

class TerraRos2BridgeCore {
public:
    TerraRos2BridgeCore(
        terra_t *terra,
        std::shared_ptr<TraceForwarder> forwarder,
        BridgeMetadata metadata = {});

    bool ingest_trace_batch(const uint8_t *data, std::size_t size);
    BridgeMetrics snapshot_metrics() const;
    std::string metrics_json() const;

private:
    void set_last_error(const std::string &message);
    void record_forward_span(std::size_t size, bool success, double duration_ms, const std::string *error);
    static std::string json_escape(const std::string &value);

    terra_t *terra_;
    std::shared_ptr<TraceForwarder> forwarder_;
    BridgeMetadata metadata_;
    std::atomic<uint64_t> payloads_received_{0};
    std::atomic<uint64_t> payloads_forwarded_{0};
    std::atomic<uint64_t> payloads_failed_{0};
    std::atomic<uint64_t> bytes_forwarded_{0};
    mutable std::mutex error_mutex_;
    std::string last_error_;
};

}  // namespace terra_ros2
