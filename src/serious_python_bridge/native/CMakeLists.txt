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
  if(WIN32)
    # Python3::Module picks pythonXY.lib (or pythonXY_d.lib in Debug builds),
    # but python-build-standalone for Windows doesn't ship a Debug variant
    # so Flutter's debug builds fail with LNK1104. Link the abi3 stable-ABI
    # stub python3.lib instead — it's version-agnostic AND has no debug
    # variant requirement (matches our Py_LIMITED_API choice).
    get_filename_component(_flet_bridge_python_root "${Python3_INCLUDE_DIRS}" DIRECTORY)
    set(FLET_BRIDGE_PYTHON_LIBRARIES "${_flet_bridge_python_root}/libs/python3.lib")
  else()
    set(FLET_BRIDGE_PYTHON_LIBRARIES Python3::Module)
  endif()
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

if(WIN32)
  # Python's pyconfig.h emits `#pragma comment(lib, "pythonXY_d.lib")` in
  # Debug builds, which makes MSVC auto-link the Debug variant of libpython
  # even though we explicitly linked python3.lib above. python-build-standalone
  # doesn't ship a Debug lib, so the link fails (LNK1104). Py_NO_LINK_LIB
  # suppresses the pragma in Python 3.14+, but 3.12 and 3.13 pyconfig.h don't
  # honor it — use /NODEFAULTLIB:pythonXY_d.lib to explicitly exclude the
  # Debug lib at link time. Works on every supported version.
  target_compile_definitions(flet_bridge PRIVATE Py_NO_LINK_LIB)
  if(Python3_VERSION_MAJOR AND Python3_VERSION_MINOR)
    target_link_options(flet_bridge PRIVATE
      "/NODEFAULTLIB:python${Python3_VERSION_MAJOR}${Python3_VERSION_MINOR}_d.lib"
    )
  endif()
endif()
