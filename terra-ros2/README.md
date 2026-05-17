# Terra ROS 2 Pilot SDK

`terra_ros2` forwards Terra OTLP trace payloads from ROS 2 systems and publishes bridge health metrics. It is intended for drone and robotics pilots on Linux companion computers; it is not flight-control middleware and is not safety-certified software.

## Supported Pilot Lanes

- Primary: ROS 2 Jazzy on Ubuntu 24.04.
- Compatibility: ROS 2 Humble on Ubuntu 22.04.
- Local fallback: package-shape validation without ROS when `colcon` is unavailable.

## Build

From the Terra repository root:

```bash
cd zig-core
zig build

cd ..
colcon build --base-paths terra-ros2 \
  --build-base .build/ros2-build \
  --install-base .build/ros2-install \
  --log-base .build/ros2-log
```

## Test

```bash
colcon test --base-paths terra-ros2 \
  --build-base .build/ros2-build \
  --install-base .build/ros2-install \
  --log-base .build/ros2-log \
  --event-handlers console_direct+
```

## Run

```bash
source .build/ros2-install/setup.bash
ros2 launch terra_ros2 terra_ros2.launch.py \
  otlp_endpoint:=http://127.0.0.1:4318 \
  robot_id:=lab-drone-01 \
  vehicle_id:=px4-sitl-01 \
  mission_id:=bench-run-001 \
  component_name:=companion-ai \
  autonomy_phase:=perception \
  content_policy:=never \
  redaction_strategy:=hmac_sha256
```

The node subscribes to `/terra/traces` as `std_msgs/msg/UInt8MultiArray` and publishes `/terra/metrics` as JSON on `std_msgs/msg/String`.

## Parameters

| Name | Default | Purpose |
| --- | --- | --- |
| `otlp_endpoint` | `http://127.0.0.1:4318` | OTLP HTTP collector base URL. |
| `metrics_interval_ms` | `5000` | Metrics publish interval. |
| `robot_id` | empty | Stable robot identity for fleet-level grouping. |
| `vehicle_id` | empty | Vehicle or airframe identity. |
| `mission_id` | empty | Mission/session identity; also used as Terra session ID when present. |
| `component_name` | `terra_ros2_node` | Companion component/service name. |
| `autonomy_phase` | empty | Current autonomy phase such as `perception`, `planning`, or `inspection`. |
| `content_policy` | `never` | Terra content capture policy: `never`, `opt_in`, or `always`. |
| `redaction_strategy` | `hmac_sha256` | Redaction mode: `drop`, `length_only`, `hmac_sha256`, or `sha256`. |

## Readiness Boundary

This package is pilot-ready when `Scripts/validate-ros2-package.sh` passes in a ROS 2 environment and trace forwarding is verified against a local OTLP collector. Production robotics readiness additionally requires green remote CI and at least one ARM64 companion-computer validation run.
