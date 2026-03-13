# =============================================================================
# CMakeLists.txt — DraftStep Geometry Library
# =============================================================================
#
# Builds the C++ geometry module as a shared library consumed by Julia
# via ccall from BezierBridge.jl.
#
# Output:
#   build/libgeometry.so    (Linux)
#   build/libgeometry.dylib (macOS)
#   build/geometry.dll      (Windows)
#
# Usage:
#   cd lib/geometry
#   cmake -B build
#   cmake --build build
#
# After building, Julia locates the library via the path in BezierBridge.jl:
#   const LIBGEOMETRY = joinpath(@__DIR__, "..", "..", "lib", "geometry",
#                                "build", "libgeometry")
#
# Requirements:
#   CMake >= 3.15
#   C++17-compatible compiler (GCC 9+, Clang 10+, MSVC 2019+)
#
# =============================================================================

cmake_minimum_required(VERSION 3.15)

project(
    DraftStepGeometry
    VERSION     1.0.0
    DESCRIPTION "High-performance geometry module for DraftStep"
    LANGUAGES   CXX
)


# =============================================================================
# SECTION 1 — Compiler settings
# =============================================================================

set(CMAKE_CXX_STANDARD          17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS        OFF)   # use -std=c++17, not -std=gnu++17

# Optimization flags for release builds
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_CXX_FLAGS_RELEASE     "-O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG       "-g -O0 -DDEBUG")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g -DNDEBUG")


# =============================================================================
# SECTION 2 — Shared library target
# =============================================================================

add_library(geometry SHARED
    bezier.cpp
)

target_include_directories(geometry
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}   # exposes bezier.hpp to consumers
)

# Ensure the output is named libgeometry on all platforms
set_target_properties(geometry PROPERTIES
    OUTPUT_NAME     "geometry"
    PREFIX          "lib"             # libgeometry.so / libgeometry.dylib
    POSITION_INDEPENDENT_CODE ON      # required for shared libraries
)

# Strict warnings — treat as errors in CI
target_compile_options(geometry PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang>:
        -Wall -Wextra -Wpedantic -Wno-unused-parameter>
    $<$<CXX_COMPILER_ID:MSVC>:
        /W4 /WX>
)


# =============================================================================
# SECTION 3 — Tests (optional, built only when testing is enabled)
# =============================================================================

option(DRAFTSTEP_BUILD_TESTS "Build C++ unit tests" OFF)

if(DRAFTSTEP_BUILD_TESTS)

    enable_testing()

    add_executable(test_bezier
        ../../tests/cpp/test_bezier.cpp
    )

    target_link_libraries(test_bezier PRIVATE geometry)

    target_include_directories(test_bezier PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
    )

    add_test(
        NAME    bezier_cpp_tests
        COMMAND test_bezier
    )

    message(STATUS "C++ tests enabled — run with: cmake --build build && ctest --test-dir build")

endif()


# =============================================================================
# SECTION 4 — Install (optional)
# =============================================================================

install(
    TARGETS geometry
    LIBRARY DESTINATION lib          # .so / .dylib
    RUNTIME DESTINATION bin          # .dll on Windows
    ARCHIVE DESTINATION lib          # .lib import library on Windows
)

install(
    FILES bezier.hpp
    DESTINATION include/draftstep
)


# =============================================================================
# SECTION 5 — Build summary
# =============================================================================

message(STATUS "")
message(STATUS "DraftStep Geometry Library")
message(STATUS "  Version      : ${PROJECT_VERSION}")
message(STATUS "  Build type   : ${CMAKE_BUILD_TYPE}")
message(STATUS "  C++ standard : C++${CMAKE_CXX_STANDARD}")
message(STATUS "  Output       : ${CMAKE_BINARY_DIR}/libgeometry${CMAKE_SHARED_LIBRARY_SUFFIX}")
message(STATUS "  Tests        : ${DRAFTSTEP_BUILD_TESTS}")
message(STATUS "")
