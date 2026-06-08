# Cross-platform CMake target for libflet_bridge.
#
# Built from the same dart_bridge.c source used by the Python shim (which CI
# builds via cibuildwheel). Per-platform wrappers under linux/, windows/, etc.
# include this file via add_subdirectory.

cmake_minimum_required(VERSION 3.15)

project(flet_bridge VERSION 0.0.1 LANGUAGES C)

# Python3::Module brings in headers + the platform-correct link behavior:
#   - Windows: links pythonXY.lib (import library)
#   - macOS:   adds -undefined dynamic_lookup
#   - Linux:   nothing (default dynamic resolution)
# Py* symbols are resolved at runtime against the libpython that serious_python
# has already loaded into the process.
find_package(Python3 REQUIRED COMPONENTS Development.Module)

add_library(flet_bridge SHARED
  "dart_bridge.c"
  "dart_api/dart_api_dl.c"
)

target_include_directories(flet_bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(flet_bridge PRIVATE Python3::Module)

set_target_properties(flet_bridge PROPERTIES
  C_VISIBILITY_PRESET hidden
  OUTPUT_NAME "flet_bridge"
)

target_compile_definitions(flet_bridge PRIVATE DART_SHARED_LIB)
