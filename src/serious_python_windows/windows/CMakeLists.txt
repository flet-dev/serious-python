# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "serious_python_windows")
if(DEFINED ENV{SERIOUS_PYTHON_VERSION})
  set(PYTHON_VERSION "$ENV{SERIOUS_PYTHON_VERSION}")
else()
  set(PYTHON_VERSION "3.14")
endif()
string(REPLACE "." "" PYTHON_VERSION_NODOT "${PYTHON_VERSION}")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "serious_python_windows_plugin")

set(PYTHON_PACKAGE ${CMAKE_BINARY_DIR}/python)
set(PYTHON_URL "https://github.com/flet-dev/python-build/releases/download/v${PYTHON_VERSION}/python-windows-for-dart-${PYTHON_VERSION}.zip")
set(PYTHON_FILE ${CMAKE_BINARY_DIR}/python-windows-for-dart.zip)
if (NOT EXISTS ${PYTHON_FILE})
  file(DOWNLOAD ${PYTHON_URL} ${PYTHON_FILE})
  file(ARCHIVE_EXTRACT INPUT ${PYTHON_FILE} DESTINATION ${PYTHON_PACKAGE})
endif()

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "serious_python_windows_plugin.cpp"
  "serious_python_windows_plugin.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/serious_python_windows/serious_python_windows_plugin_c_api.h"
  "serious_python_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

include_directories(
  "${PYTHON_PACKAGE}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Always link/bundle the Release Python regardless of Flutter's build config.
# Reason: Python C extension wheels (including the cibuildwheel-built abi3
# dart_bridge shim downloaded by `package_command.dart --bridge`) are compiled
# against Release CPython and reference Release python3.dll / pythonXY.dll. A
# Debug Flutter build that bundled pythonXY_d.dll couldn't load those wheels.
# python-build-standalone also doesn't ship a Debug variant in the same shape,
# so a single Release Python is the consistent ABI target.
#
# In Debug Flutter builds, pyconfig.h emits `#pragma comment(lib,
# "pythonXY_d.lib")` to ask MSVC to auto-link the Debug Python lib. That lib
# isn't shipped by python-build-standalone, so the link fails with LNK1104.
# Py_NO_LINK_LIB (Python 3.14+) would suppress that pragma but 3.12 and 3.13
# pyconfig.h doesn't honor it — so use /NODEFAULTLIB to explicitly exclude
# the Debug lib request at link time. Works across all supported versions.
target_link_libraries(${PLUGIN_NAME} PRIVATE
  "${PYTHON_PACKAGE}/libs/python${PYTHON_VERSION_NODOT}.lib"
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE Py_NO_LINK_LIB)
target_link_options(${PLUGIN_NAME} PRIVATE
  "/NODEFAULTLIB:python${PYTHON_VERSION_NODOT}_d.lib"
)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
string(REPLACE "\\" "/" SERIOUS_PYTHON_WINDIR "$ENV{WINDIR}")
set(serious_python_windows_bundled_libraries
  "${PYTHON_PACKAGE}/python${PYTHON_VERSION_NODOT}.dll"
  "${PYTHON_PACKAGE}/python3.dll"
  "${SERIOUS_PYTHON_WINDIR}/System32/msvcp140.dll"
  "${SERIOUS_PYTHON_WINDIR}/System32/vcruntime140.dll"
  "${SERIOUS_PYTHON_WINDIR}/System32/vcruntime140_1.dll"
  PARENT_SCOPE
)

# Copy Python libraries
add_custom_target(CopyPythonDLLs ALL DEPENDS PYTHON_PACKAGE_DOWNLOAD)
add_custom_command(TARGET CopyPythonDLLs POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>"
  COMMAND ${CMAKE_COMMAND} -E copy_directory 
    "${PYTHON_PACKAGE}/Lib"
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/Lib"
  COMMAND ${CMAKE_COMMAND} -E copy_directory 
    "${PYTHON_PACKAGE}/DLLs"
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs"
  COMMAND DEL \"${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs\\*_d.*\" /S /Q
  COMMAND DEL \"${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs\\*.ico\" /S /Q
  COMMAND DEL \"${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs\\*.cat\" /S /Q
  COMMAND DEL \"${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs\\tcl86t.dll\" /Q
  COMMAND DEL \"${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs\\tk86t.dll\" /Q
)

if(DEFINED ENV{SERIOUS_PYTHON_SITE_PACKAGES})
  add_custom_command(TARGET CopyPythonDLLs POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E remove_directory
      "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/site-packages"
    COMMAND ${CMAKE_COMMAND} -E make_directory
      "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/site-packages"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "$ENV{SERIOUS_PYTHON_SITE_PACKAGES}"
      "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/site-packages"
  )
endif()
