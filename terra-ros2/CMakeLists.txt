cmake_minimum_required(VERSION 3.14)
project(terra_ros2)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
find_package(CURL REQUIRED)

# Link libtera
add_library(terra STATIC IMPORTED)
set_target_properties(terra PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/zig-out/lib/libtera.a")
target_include_directories(terra INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/include")

add_library(terra_ros2_bridge_core src/terra_ros2_bridge_core.cpp)
target_include_directories(
  terra_ros2_bridge_core
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/include"
)
target_link_libraries(terra_ros2_bridge_core terra CURL::libcurl)

# Terra ROS 2 node
add_executable(terra_ros2_node src/terra_ros2_node.cpp)
ament_target_dependencies(terra_ros2_node rclcpp std_msgs)
target_link_libraries(terra_ros2_node terra_ros2_bridge_core)

if(BUILD_TESTING)
  find_package(ament_cmake_gtest REQUIRED)
  ament_add_gtest(
    terra_ros2_bridge_core_test
    tests/terra_ros2_bridge_core_test.cpp
  )
  if(TARGET terra_ros2_bridge_core_test)
    target_link_libraries(terra_ros2_bridge_core_test terra_ros2_bridge_core)
    target_include_directories(
      terra_ros2_bridge_core_test
      PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
        "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/include"
    )
  endif()
endif()

install(TARGETS terra_ros2_bridge_core terra_ros2_node DESTINATION lib/${PROJECT_NAME})
ament_package()
