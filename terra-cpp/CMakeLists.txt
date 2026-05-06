cmake_minimum_required(VERSION 3.14)
project(terra_cpp_example LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(
    TERRA_LIB_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/../zig-core/zig-out/lib/libterra.a"
    CACHE FILEPATH "Path to libterra.a produced by `cd ../zig-core && zig build`"
)

if(NOT EXISTS "${TERRA_LIB_PATH}")
    message(
        FATAL_ERROR
        "Missing libterra.a at ${TERRA_LIB_PATH}. "
        "From a clean checkout, run `cd ../zig-core && zig build` before configuring terra-cpp, "
        "or pass -DTERRA_LIB_PATH=/absolute/path/to/libterra.a."
    )
endif()

# Import the pre-built Terra static library from zig-core
add_library(terra STATIC IMPORTED)
set_target_properties(terra PROPERTIES
    IMPORTED_LOCATION "${TERRA_LIB_PATH}"
)

# Example executable
add_executable(basic examples/basic.cpp)
target_include_directories(basic PRIVATE
    include
    ../zig-core/include
)
target_link_libraries(basic terra)

enable_testing()

add_executable(string_view_smoke tests/string_view_smoke.cpp)
target_include_directories(string_view_smoke PRIVATE
    include
    ../zig-core/include
)
target_link_libraries(string_view_smoke terra)
add_test(NAME string_view_smoke COMMAND string_view_smoke)
