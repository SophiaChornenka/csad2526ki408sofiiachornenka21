#!/bin/bash
set -e

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Run CMake configuration
cmake ..

# Build the project
cmake --build .

# Run tests with output on failure
ctest --output-on-failure
