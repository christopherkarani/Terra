#include <chrono>
#include <functional>
#include <memory>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "std_msgs/msg/u_int8_multi_array.hpp"

#include "terra_ros2_bridge_core.hpp"

extern "C" {
#include "terra.h"
}

using namespace std::chrono_literals;

class TerraRos2Node : public rclcpp::Node {
public:
    TerraRos2Node() : Node("terra_ros2_node") {
        const std::string otlp_endpoint =
            this->declare_parameter<std::string>("otlp_endpoint", "http://127.0.0.1:4318");
        const int metrics_interval_ms =
            this->declare_parameter<int>("metrics_interval_ms", 5000);
        const std::string robot_id =
            this->declare_parameter<std::string>("robot_id", "");
        const std::string vehicle_id =
            this->declare_parameter<std::string>("vehicle_id", "");
        const std::string mission_id =
            this->declare_parameter<std::string>("mission_id", "");
        const std::string component_name =
            this->declare_parameter<std::string>("component_name", "terra_ros2_node");
        const std::string autonomy_phase =
            this->declare_parameter<std::string>("autonomy_phase", "");
        const std::string content_policy =
            this->declare_parameter<std::string>("content_policy", "never");
        const std::string redaction_strategy =
            this->declare_parameter<std::string>("redaction_strategy", "hmac_sha256");

        // Initialize Terra with default config
        terra_config_t config = {};
        config.service_name = component_name.c_str();
        config.service_version = "1.0.0";
        config.otlp_endpoint = otlp_endpoint.c_str();
        config.content_policy = parse_content_policy(content_policy);
        config.redaction_strategy = parse_redaction_strategy(redaction_strategy);
        terra_ = terra_init(&config);

        if (!terra_) {
            RCLCPP_ERROR(this->get_logger(), "Failed to initialize Terra instance");
        } else {
            RCLCPP_INFO(this->get_logger(), "Terra instance initialized");
            if (!mission_id.empty()) {
                terra_set_session_id(terra_, mission_id.c_str());
            }
        }

        terra_ros2::BridgeMetadata metadata;
        metadata.robot_id = robot_id;
        metadata.vehicle_id = vehicle_id;
        metadata.mission_id = mission_id;
        metadata.component_name = component_name;
        metadata.autonomy_phase = autonomy_phase;
        metadata.content_policy = content_policy;
        metadata.redaction_strategy = redaction_strategy;

        bridge_ = std::make_unique<terra_ros2::TerraRos2BridgeCore>(
            terra_,
            std::make_shared<terra_ros2::CurlTraceForwarder>(otlp_endpoint),
            metadata);

        // Subscribe to trace data (raw bytes as UInt8MultiArray)
        trace_sub_ = this->create_subscription<std_msgs::msg::UInt8MultiArray>(
            "/terra/traces", 10,
            std::bind(&TerraRos2Node::trace_callback, this, std::placeholders::_1));

        // Publisher for aggregated metrics (JSON string)
        metrics_pub_ = this->create_publisher<std_msgs::msg::String>("/terra/metrics", 10);

        // Periodic metrics publishing timer (every 5 seconds)
        metrics_timer_ = this->create_wall_timer(
            std::chrono::milliseconds(metrics_interval_ms),
            std::bind(&TerraRos2Node::publish_metrics, this));

        RCLCPP_INFO(this->get_logger(),
                     "Terra ROS 2 node started — forwarding /terra/traces to %s and publishing metrics to /terra/metrics",
                     otlp_endpoint.c_str());
    }

    ~TerraRos2Node() {
        if (terra_) {
            terra_shutdown(terra_);
            RCLCPP_INFO(this->get_logger(), "Terra instance shut down");
        }
    }

private:
    static terra_content_policy_t parse_content_policy(const std::string &value) {
        if (value == "opt_in") return TERRA_CONTENT_OPT_IN;
        if (value == "always") return TERRA_CONTENT_ALWAYS;
        return TERRA_CONTENT_NEVER;
    }

    static terra_redaction_strategy_t parse_redaction_strategy(const std::string &value) {
        if (value == "drop") return TERRA_REDACT_DROP;
        if (value == "length_only") return TERRA_REDACT_LENGTH_ONLY;
        if (value == "sha256") return TERRA_REDACT_SHA256;
        return TERRA_REDACT_HMAC_SHA256;
    }

    void trace_callback(const std_msgs::msg::UInt8MultiArray::SharedPtr msg) {
        if (!bridge_) return;

        const bool forwarded = bridge_->ingest_trace_batch(msg->data.data(), msg->data.size());
        if (forwarded) {
            RCLCPP_DEBUG(
                this->get_logger(),
                "Forwarded %zu OTLP bytes from /terra/traces",
                msg->data.size());
        } else {
            RCLCPP_WARN(
                this->get_logger(),
                "Failed to forward %zu OTLP bytes from /terra/traces",
                msg->data.size());
        }
    }

    void publish_metrics() {
        if (!bridge_) return;

        auto msg = std_msgs::msg::String();
        msg.data = bridge_->metrics_json();

        metrics_pub_->publish(msg);
        RCLCPP_DEBUG(this->get_logger(), "Published metrics: %s", msg.data.c_str());
    }

    terra_t *terra_ = nullptr;
    std::unique_ptr<terra_ros2::TerraRos2BridgeCore> bridge_;

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
