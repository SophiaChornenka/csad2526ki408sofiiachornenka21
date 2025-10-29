cmake_minimum_required(VERSION 3.10)

# Project name
project(hello_project LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Force dynamic runtime library (/MD) for consistency
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

# Add executable
add_executable(hello main.cpp math_operations.cpp)

# Add Google Test support
include(FetchContent)
FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/release-1.12.1.tar.gz
)
# Force Google Test to use dynamic runtime
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
# Make googletest available
FetchContent_MakeAvailable(googletest)
enable_testing()

# Add test executable
add_executable(unit_tests
    tests/unit_tests.cpp
    math_operations.cpp
)
target_link_libraries(unit_tests
    PRIVATE
        GTest::gtest
        GTest::gtest_main
)
target_include_directories(unit_tests
    PRIVATE
        ${PROJECT_SOURCE_DIR}
)
include(GoogleTest)
gtest_discover_tests(unit_tests)
