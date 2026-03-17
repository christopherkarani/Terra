cmake_minimum_required(VERSION 3.14)
project(terra_ros2)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)

# Link libtera
add_library(terra STATIC IMPORTED)
set_target_properties(terra PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/zig-out/lib/libtera.a")
target_include_directories(terra INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/include")

# Terra ROS 2 node
add_executable(terra_ros2_node src/terra_ros2_node.cpp)
ament_target_dependencies(terra_ros2_node rclcpp std_msgs)
target_link_libraries(terra_ros2_node terra)

install(TARGETS terra_ros2_node DESTINATION lib/${PROJECT_NAME})
ament_package()
