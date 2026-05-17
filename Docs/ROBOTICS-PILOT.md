# Terra Robotics Pilot Readiness

Terra can be piloted by drone and robotics teams as an observability layer for AI/autonomy workflows on companion computers, controllers, and lab robots. Terra is not flight-control middleware, does not replace ROS 2/DDS/MAVLink, and is not safety-certified software.

## First Supported Surface

- Primary lane: ROS 2 Jazzy on Ubuntu 24.04.
- Compatibility lane: ROS 2 Humble on Ubuntu 22.04.
- First package: `terra-ros2`, which forwards OTLP trace payloads from `/terra/traces` and publishes bridge health to `/terra/metrics`.

## Pilot Contract

Robotics pilots should emit or configure:

- `terra.robot.id` for stable robot identity.
- `terra.vehicle.id` for airframe or controller identity.
- `terra.mission.id` for mission/session grouping.
- `terra.component.name` for the companion component or ROS node.
- `terra.autonomy.phase` for phases such as `perception`, `planning`, `control`, or `inspection`.
- `terra.transport.protocol` for `otlp_http`, `mqtt`, `coap`, or `uart`.
- `terra.privacy.content_policy` and `terra.privacy.redaction_strategy` for privacy posture.

The ROS 2 bridge applies these attributes to its own forwarding spans. Application and autonomy code should keep using Terra's normal workflow/inference/tool spans and attach the same identifiers where needed.

## Embedded Transport Boundary

The C ABI exposes callback-backed helpers for MQTT, CoAP, and UART transports. Terra owns OTLP payload framing; the host owns the actual network, serial, broker, socket, or firmware client lifecycle. Keep the config structs and platform client handles alive for as long as the Terra instance uses the returned transport vtable.

## Readiness Gates

Pilot-ready means:

1. `Scripts/validate.sh --quick` passes locally.
2. `Scripts/validate-ros2-package.sh` passes in a ROS 2 environment.
3. A local OTLP collector receives trace payloads forwarded by `terra_ros2_node`.
4. The deployment keeps content capture at `never` or `opt_in` unless the pilot explicitly approves raw content.

Production robotics-ready additionally requires green remote CI, ROS 2 Jazzy/Humble matrix proof, Linux ARM64 validation on a companion-computer class target, documented offline/degraded-link behavior, and a customer pilot checklist.
