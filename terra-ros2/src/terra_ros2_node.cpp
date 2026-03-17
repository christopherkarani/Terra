// Terra ROS 2 Node — Bridge between ROS 2 topics and Terra observability.
//
// Subscribes to /terra/traces (raw OTLP protobuf bytes) and forwards them
// to a local Terra instance for processing. Publishes aggregated metrics
// to /terra/metrics as JSON strings.
//
// Usage:
//   ros2 run terra_ros2 terra_ros2_node
//
// This is a stub implementation. The actual OTLP processing and metric
// aggregation will be wired up once the C ABI is finalized for batch ingest.

#include <chrono>
#include <functional>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "std_msgs/msg/u_int8_multi_array.hpp"

extern "C" {
#include "terra.h"
}

using namespace std::chrono_literals;

class TerraRos2Node : public rclcpp::Node {
public:
    TerraRos2Node() : Node("terra_ros2_node") {
        // Initialize Terra with default config
        terra_config_t config = {};
        config.service_name = "terra-ros2";
        config.service_version = "0.1.0";
        terra_ = terra_init(&config);

        if (!terra_) {
            RCLCPP_ERROR(this->get_logger(), "Failed to initialize Terra instance");
        } else {
            RCLCPP_INFO(this->get_logger(), "Terra instance initialized");
        }

        // Subscribe to trace data (raw bytes as UInt8MultiArray)
        trace_sub_ = this->create_subscription<std_msgs::msg::UInt8MultiArray>(
            "/terra/traces", 10,
            std::bind(&TerraRos2Node::trace_callback, this, std::placeholders::_1));

        // Publisher for aggregated metrics (JSON string)
        metrics_pub_ = this->create_publisher<std_msgs::msg::String>("/terra/metrics", 10);

        // Periodic metrics publishing timer (every 5 seconds)
        metrics_timer_ = this->create_wall_timer(
            5s, std::bind(&TerraRos2Node::publish_metrics, this));

        RCLCPP_INFO(this->get_logger(),
                     "Terra ROS 2 node started — listening on /terra/traces, publishing to /terra/metrics");
    }

    ~TerraRos2Node() {
        if (terra_) {
            terra_shutdown(terra_);
            RCLCPP_INFO(this->get_logger(), "Terra instance shut down");
        }
    }

private:
    void trace_callback(const std_msgs::msg::UInt8MultiArray::SharedPtr msg) {
        if (!terra_ || msg->data.empty()) return;

        // TODO: Forward raw OTLP bytes to Terra for local processing.
        // The C ABI for batch ingest is not yet exposed — this is a placeholder.
        // Future: terra_ingest_otlp(terra_, msg->data.data(), msg->data.size());
        RCLCPP_DEBUG(this->get_logger(),
                      "Received %zu bytes of trace data", msg->data.size());

        spans_received_ += 1;
    }

    void publish_metrics() {
        if (!terra_) return;

        auto msg = std_msgs::msg::String();

        // Gather diagnostics from Terra
        uint64_t dropped = terra_spans_dropped(terra_);
        bool degraded = terra_transport_degraded(terra_);
        uint8_t state = terra_get_state(terra_);

        // Build JSON metrics payload
        msg.data = "{"
            "\"spans_received\":" + std::to_string(spans_received_) + ","
            "\"spans_dropped\":" + std::to_string(dropped) + ","
            "\"transport_degraded\":" + (degraded ? "true" : "false") + ","
            "\"lifecycle_state\":" + std::to_string(state) +
            "}";

        metrics_pub_->publish(msg);
        RCLCPP_DEBUG(this->get_logger(), "Published metrics: %s", msg.data.c_str());
    }

    terra_t *terra_ = nullptr;
    uint64_t spans_received_ = 0;

    rclcpp::Subscription<std_msgs::msg::UInt8MultiArray>::SharedPtr trace_sub_;
    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr metrics_pub_;
    rclcpp::TimerBase::SharedPtr metrics_timer_;
};

int main(int argc, char *argv[]) {
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<TerraRos2Node>());
    rclcpp::shutdown();
    return 0;
}
