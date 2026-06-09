cmake_minimum_required(VERSION 3.15)

set(PROJECT_NAME "serious_python_bridge")
project(${PROJECT_NAME} LANGUAGES C)

cmake_policy(VERSION 3.15...3.25)

# flet_bridge.dll's import table must reference python3.dll in Release Flutter
# builds and python3_d.dll in Debug builds — to match the python<XY>(_d).dll
# bundled by serious_python_windows. find_package(Python3) only points at the
# system Python's libs/ folder, which typically lacks python<XY>_d.lib, so
# Debug builds would fail to link (the auto-link pragma in pyconfig.h asks for
# python<XY>_d.lib). Download the same python-windows-for-dart tarball that
# serious_python_windows uses — it ships both Release and Debug abi3 stubs
# (libs/python3.lib + libs/python3_d.lib) plus Debug-variant pythonXY_d.lib.
if(DEFINED ENV{SERIOUS_PYTHON_VERSION})
  set(PYTHON_VERSION "$ENV{SERIOUS_PYTHON_VERSION}")
else()
  set(PYTHON_VERSION "3.14")
endif()
set(PYTHON_DOWNLOAD_DIR "${CMAKE_BINARY_DIR}/python_dist")
set(PYTHON_ZIP "${CMAKE_BINARY_DIR}/python-windows-for-dart-${PYTHON_VERSION}.zip")
if(NOT EXISTS "${PYTHON_DOWNLOAD_DIR}/include/Python.h")
  if(NOT EXISTS "${PYTHON_ZIP}")
    file(DOWNLOAD
      "https://github.com/flet-dev/python-build/releases/download/v${PYTHON_VERSION}/python-windows-for-dart-${PYTHON_VERSION}.zip"
      "${PYTHON_ZIP}")
  endif()
  file(MAKE_DIRECTORY "${PYTHON_DOWNLOAD_DIR}")
  file(ARCHIVE_EXTRACT INPUT "${PYTHON_ZIP}"
    DESTINATION "${PYTHON_DOWNLOAD_DIR}")
endif()

set(FLET_BRIDGE_PYTHON_INCLUDE_DIRS "${PYTHON_DOWNLOAD_DIR}/include")
# Pick Debug abi3 stub (python3_d.lib) when Flutter is building Debug, Release
# stub (python3.lib) otherwise. The corresponding python3(_d).dll is bundled
# by serious_python_windows.
set(FLET_BRIDGE_PYTHON_LIBRARIES
  "${PYTHON_DOWNLOAD_DIR}/libs/python3$<$<CONFIG:Debug>:_d>.lib"
)

add_subdirectory("../native" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Make python-windows-for-dart's libs/ visible to MSVC's auto-link. pyconfig.h
# emits `#pragma comment(lib, "pythonXY(_d).lib")` and MSVC's default LIB path
# wouldn't find the file otherwise. The tarball ships pythonXY.lib AND
# pythonXY_d.lib for every version, so both Debug and Release auto-link
# resolve. (We pass /NODEFAULTLIB in native/CMakeLists for the cibuildwheel
# setup.py build path, but here the request can be satisfied properly so we
# let it through.)
target_link_directories(flet_bridge PRIVATE "${PYTHON_DOWNLOAD_DIR}/libs")

# Flutter picks up bundled libraries via this variable and copies the file
# alongside the app binary; Dart resolves it via DynamicLibrary.open.
#
# The bridge plugin only ships flet_bridge.dll. python3.dll / python3_d.dll
# (the abi3 stable-ABI loader that dart_bridge.pyd imports) is bundled by
# serious_python_windows, which already chooses the correct Debug/Release
# variant matching Flutter's build config.
set(serious_python_bridge_bundled_libraries
  $<TARGET_FILE:flet_bridge>
  PARENT_SCOPE
)
