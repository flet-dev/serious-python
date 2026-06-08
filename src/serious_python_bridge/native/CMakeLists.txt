# Cross-platform CMake target for libflet_bridge.
#
# Built from the same dart_bridge.c source used by the Python shim. Per-platform
# wrappers under linux/, windows/, android/ include this file via add_subdirectory.
#
# Python integration:
#   - If FLET_BRIDGE_PYTHON_INCLUDE_DIRS + FLET_BRIDGE_PYTHON_LIBRARIES are set
#     before add_subdirectory, those are used (Android uses this path to point
#     at the python-android-dart tarball it downloads).
#   - Otherwise we use find_package(Python3 ... Development.Module) + the
#     Python3::Module imported target, which handles Linux/macOS/Windows link
#     conventions automatically.

cmake_minimum_required(VERSION 3.15)

project(flet_bridge VERSION 0.0.1 LANGUAGES C)

if(NOT DEFINED FLET_BRIDGE_PYTHON_INCLUDE_DIRS)
  find_package(Python3 REQUIRED COMPONENTS Development.Module)
  set(FLET_BRIDGE_PYTHON_INCLUDE_DIRS ${Python3_INCLUDE_DIRS})
  set(FLET_BRIDGE_PYTHON_LIBRARIES Python3::Module)
endif()

add_library(flet_bridge SHARED
  "dart_bridge.c"
  "dart_api/dart_api_dl.c"
)

target_include_directories(flet_bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  ${FLET_BRIDGE_PYTHON_INCLUDE_DIRS}
)

target_link_libraries(flet_bridge PRIVATE ${FLET_BRIDGE_PYTHON_LIBRARIES})

set_target_properties(flet_bridge PROPERTIES
  C_VISIBILITY_PRESET hidden
  OUTPUT_NAME "flet_bridge"
)

target_compile_definitions(flet_bridge PRIVATE DART_SHARED_LIB)
