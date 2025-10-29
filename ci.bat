@echo off
REM Continuous Integration script for Windows using CMake and CTest

REM Create build directory
if not exist build (
    mkdir build
)

REM Change to build directory
cd build

REM Configure the project
cmake .. || exit /b 1

REM Build the project in Release configuration
cmake --build . --config Release || exit /b 1

REM Run tests with output on failure
ctest --output-on-failure || exit /b 1
