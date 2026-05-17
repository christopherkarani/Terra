#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test -f terra-ros2/package.xml || fail "terra-ros2/package.xml is missing"
test -f terra-ros2/CMakeLists.txt || fail "terra-ros2/CMakeLists.txt is missing"
test -f terra-ros2/README.md || fail "terra-ros2/README.md is missing"
test -f terra-ros2/launch/terra_ros2.launch.py || fail "terra-ros2 launch file is missing"

rg -q 'robot_id' terra-ros2/src/terra_ros2_node.cpp || fail "robot_id parameter is not declared"
rg -q 'vehicle_id' terra-ros2/src/terra_ros2_node.cpp || fail "vehicle_id parameter is not declared"
rg -q 'mission_id' terra-ros2/src/terra_ros2_node.cpp || fail "mission_id parameter is not declared"
rg -q 'content_policy' terra-ros2/src/terra_ros2_node.cpp || fail "content_policy parameter is not declared"
rg -q 'redaction_strategy' terra-ros2/src/terra_ros2_node.cpp || fail "redaction_strategy parameter is not declared"
rg -q 'install\(DIRECTORY launch' terra-ros2/CMakeLists.txt || fail "launch files are not installed"

if ! command -v colcon >/dev/null 2>&1; then
  echo "SKIP: colcon is not installed; ROS 2 package shape checks passed."
  exit 0
fi

if ! command -v zig >/dev/null 2>&1; then
  fail "zig is required before running colcon validation"
fi

(
  cd zig-core
  zig build
)

colcon build --base-paths terra-ros2 \
  --build-base .build/ros2-build \
  --install-base .build/ros2-install \
  --log-base .build/ros2-log

colcon test --base-paths terra-ros2 \
  --build-base .build/ros2-build \
  --install-base .build/ros2-install \
  --log-base .build/ros2-log \
  --event-handlers console_direct+
