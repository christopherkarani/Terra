cmake_minimum_required(VERSION 3.14)
project(terra_cpp_example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Import the pre-built Terra static library from zig-core
add_library(terra STATIC IMPORTED)
set_target_properties(terra PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/zig-out/lib/libtera.a"
)

# Example executable
add_executable(basic examples/basic.cpp)
target_include_directories(basic PRIVATE
    include
    ../zig-core/include
)
target_link_libraries(basic terra)
