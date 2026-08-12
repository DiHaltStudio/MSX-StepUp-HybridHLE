cmake_minimum_required(VERSION 3.22)
project(z80_plugin LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── godot-cpp ─────────────────────────────────────────────────────────────────
set(GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/godot-cpp")

# Tell godot-cpp where to find the Godot-generated API files
set(GODOT_GDEXTENSION_DIR "${GODOT_CPP_DIR}" CACHE PATH "Path to gdextension files")

add_subdirectory(${GODOT_CPP_DIR} godot-cpp)

# ── Plugin shared library ─────────────────────────────────────────────────────
add_library(z80_plugin SHARED
    src/register_types.cpp
    src/z80_node.cpp
    src/doc_data.cpp
)

target_include_directories(z80_plugin PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/chips
    ${GODOT_CPP_DIR}/include
    ${GODOT_CPP_DIR}/gdextension
)

target_link_libraries(z80_plugin PRIVATE godot-cpp)

# Release artifacts should not depend on the build machine's exact libstdc++
# version. glibc remains dynamically linked, so CI uses Ubuntu 22.04 as a
# conservative baseline for the Linux package.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(z80_plugin PRIVATE -static-libgcc -static-libstdc++)
endif()

# ── Compiler flags ────────────────────────────────────────────────────────────
target_compile_options(z80_plugin PRIVATE
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
    "$<$<NOT:$<CXX_COMPILER_ID:MSVC>>:-Wall;-Wno-unused-parameter>"
)

# Keep one deterministic directory per Godot platform and architecture. The
# paths match z80_plugin.gdextension and allow CI jobs to merge their artifacts.
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(Z80_GODOT_PLATFORM "android")
    if(ANDROID_ABI STREQUAL "arm64-v8a")
        set(Z80_GODOT_ARCH "arm64")
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
        set(Z80_GODOT_ARCH "arm32")
    elseif(ANDROID_ABI STREQUAL "x86_64")
        set(Z80_GODOT_ARCH "x86_64")
    else()
        message(FATAL_ERROR "Unsupported Android ABI: ${ANDROID_ABI}")
    endif()
elseif(APPLE)
    set(Z80_GODOT_PLATFORM "macos")
    if("x86_64" IN_LIST CMAKE_OSX_ARCHITECTURES AND "arm64" IN_LIST CMAKE_OSX_ARCHITECTURES)
        set(Z80_GODOT_ARCH "universal")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(Z80_GODOT_ARCH "arm64")
    else()
        set(Z80_GODOT_ARCH "x86_64")
    endif()
elseif(WIN32)
    set(Z80_GODOT_PLATFORM "windows")
    set(Z80_GODOT_ARCH "x86_64")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(Z80_GODOT_PLATFORM "linux")
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(Z80_GODOT_ARCH "arm64")
    else()
        set(Z80_GODOT_ARCH "x86_64")
    endif()
else()
    message(FATAL_ERROR "Unsupported target platform: ${CMAKE_SYSTEM_NAME}")
endif()

set(Z80_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin/${Z80_GODOT_PLATFORM}/${Z80_GODOT_ARCH}")
set_target_properties(z80_plugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${Z80_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${Z80_OUTPUT_DIR}"
)

message(STATUS "z80_plugin output directory: ${Z80_OUTPUT_DIR}")
