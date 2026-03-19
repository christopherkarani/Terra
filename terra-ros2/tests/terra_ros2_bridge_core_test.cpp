#include "terra_ros2_bridge_core.hpp"

#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

class FakeForwarder final : public terra_ros2::TraceForwarder {
public:
    bool should_succeed = true;
    std::string failure_message = "forced transport failure";
    std::size_t calls = 0;
    std::size_t last_payload_size = 0;

    bool post_traces(const uint8_t *data, std::size_t size, std::string *error) override {
        ++calls;
        last_payload_size = size;
        if (data == nullptr || size == 0) {
            if (error != nullptr) *error = "empty OTLP trace payload";
            return false;
        }
        if (!should_succeed) {
            if (error != nullptr) *error = failure_message;
            return false;
        }
        return true;
    }
};

void require(bool condition, const std::string &message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

terra_t *make_terra() {
    terra_config_t config = {};
    config.service_name = "terra-ros2-test";
    config.service_version = "1.0.0";
    return terra_init(&config);
}

}  // namespace

int main() {
    int failed = 0;

    auto run = [&](const char *name, const auto &body) {
        try {
            body();
            std::cout << "[PASS] " << name << '\n';
        } catch (const std::exception &ex) {
            std::cerr << "[FAIL] " << name << ": " << ex.what() << '\n';
            ++failed;
        }
    };

    run("successful ingest updates counters", [] {
        terra_t *terra = make_terra();
        require(terra != nullptr, "terra_init failed");
        auto forwarder = std::make_shared<FakeForwarder>();
        terra_ros2::TerraRos2BridgeCore bridge(terra, forwarder);

        const std::vector<uint8_t> payload = {0x0A, 0x01, 0x01, 0x12, 0x00};
        require(bridge.ingest_trace_batch(payload.data(), payload.size()), "ingest should succeed");

        const auto metrics = bridge.snapshot_metrics();
        require(metrics.payloads_received == 1, "payloads_received mismatch");
        require(metrics.payloads_forwarded == 1, "payloads_forwarded mismatch");
        require(metrics.payloads_failed == 0, "payloads_failed mismatch");
        require(metrics.bytes_forwarded == payload.size(), "bytes_forwarded mismatch");
        require(metrics.lifecycle_state == TERRA_STATE_RUNNING, "lifecycle state mismatch");
        require(forwarder->calls == 1, "forwarder was not called once");

        terra_shutdown(terra);
    });

    run("failed ingest captures error", [] {
        terra_t *terra = make_terra();
        require(terra != nullptr, "terra_init failed");
        auto forwarder = std::make_shared<FakeForwarder>();
        forwarder->should_succeed = false;
        forwarder->failure_message = "collector unavailable";
        terra_ros2::TerraRos2BridgeCore bridge(terra, forwarder);

        const std::vector<uint8_t> payload = {0x0A, 0x02, 0xDE, 0xAD};
        require(!bridge.ingest_trace_batch(payload.data(), payload.size()), "ingest should fail");

        const auto metrics = bridge.snapshot_metrics();
        require(metrics.payloads_received == 1, "payloads_received mismatch");
        require(metrics.payloads_forwarded == 0, "payloads_forwarded mismatch");
        require(metrics.payloads_failed == 1, "payloads_failed mismatch");
        require(metrics.last_error == "collector unavailable", "last_error mismatch");
        require(bridge.metrics_json().find("collector unavailable") != std::string::npos, "metrics json missing error");

        terra_shutdown(terra);
    });

    run("empty payload is rejected", [] {
        terra_t *terra = make_terra();
        require(terra != nullptr, "terra_init failed");
        auto forwarder = std::make_shared<FakeForwarder>();
        terra_ros2::TerraRos2BridgeCore bridge(terra, forwarder);

        require(!bridge.ingest_trace_batch(nullptr, 0), "empty payload should fail");

        const auto metrics = bridge.snapshot_metrics();
        require(metrics.payloads_received == 1, "payloads_received mismatch");
        require(metrics.payloads_failed == 1, "payloads_failed mismatch");
        require(metrics.last_error == "empty OTLP trace payload", "last_error mismatch");
        require(forwarder->calls == 0, "forwarder should not be called for empty payloads");

        terra_shutdown(terra);
    });

    if (failed != 0) {
        return 1;
    }

    std::cout << "[PASS] all terra_ros2 bridge core tests\n";
    return 0;
}
