from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    arguments = [
        ("otlp_endpoint", "http://127.0.0.1:4318"),
        ("metrics_interval_ms", "5000"),
        ("robot_id", ""),
        ("vehicle_id", ""),
        ("mission_id", ""),
        ("component_name", "terra_ros2_node"),
        ("autonomy_phase", ""),
        ("content_policy", "never"),
        ("redaction_strategy", "hmac_sha256"),
    ]

    return LaunchDescription(
        [
            *[
                DeclareLaunchArgument(name, default_value=default)
                for name, default in arguments
            ],
            Node(
                package="terra_ros2",
                executable="terra_ros2_node",
                name="terra_ros2_node",
                output="screen",
                parameters=[
                    {
                        name: LaunchConfiguration(name)
                        for name, _default in arguments
                    }
                ],
            ),
        ]
    )
