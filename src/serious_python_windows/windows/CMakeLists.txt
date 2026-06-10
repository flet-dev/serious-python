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
if(DEFINED ENV{DART_BRIDGE_VERSION})
  set(DART_BRIDGE_VERSION "$ENV{DART_BRIDGE_VERSION}")
else()
  set(DART_BRIDGE_VERSION "1.2.1")
endif()
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "serious_python_windows_plugin")

# ---- python-windows-for-dart (runtime DLLs + stdlib) ----------------------
# python3X.dll, python3.dll, Lib/, DLLs/ — required at runtime so the embedded
# CPython (driven by libdart_bridge.dll) can find its stdlib and the abi3 stub
# python3.dll can forward to python3X.dll. We no longer need the .lib / headers
# here because no Python C API call sites live in this plugin anymore.
set(PYTHON_PACKAGE ${CMAKE_BINARY_DIR}/python)
set(PYTHON_URL "https://github.com/flet-dev/python-build/releases/download/v${PYTHON_VERSION}/python-windows-for-dart-${PYTHON_VERSION}.zip")
set(PYTHON_FILE ${CMAKE_BINARY_DIR}/python-windows-for-dart.zip)
if (NOT EXISTS ${PYTHON_FILE})
  file(DOWNLOAD ${PYTHON_URL} ${PYTHON_FILE})
  file(ARCHIVE_EXTRACT INPUT ${PYTHON_FILE} DESTINATION ${PYTHON_PACKAGE})
endif()

# ---- dart_bridge prebuilt DLLs --------------------------------------------
# Release CRT (.dll) is what Release Flutter builds consume; Debug CRT
# (_d.dll) is what `fvm flutter run` / Debug builds consume. Both ship in
# every release of flet-dev/dart-bridge; we bundle both and let Flutter's
# CONFIG-aware copy machinery pick the right one at app launch time.
set(DART_BRIDGE_DIR ${CMAKE_BINARY_DIR}/dart_bridge)
set(DART_BRIDGE_RELEASE_DLL "${DART_BRIDGE_DIR}/dart_bridge.dll")
set(DART_BRIDGE_DEBUG_DLL   "${DART_BRIDGE_DIR}/dart_bridge_d.dll")
file(MAKE_DIRECTORY ${DART_BRIDGE_DIR})
if(NOT EXISTS "${DART_BRIDGE_RELEASE_DLL}")
  file(DOWNLOAD
    "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/dart_bridge-windows-x86_64.dll"
    "${DART_BRIDGE_RELEASE_DLL}")
endif()
if(NOT EXISTS "${DART_BRIDGE_DEBUG_DLL}")
  file(DOWNLOAD
    "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/dart_bridge_d-windows-x86_64.dll"
    "${DART_BRIDGE_DEBUG_DLL}")
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

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
string(REPLACE "\\" "/" SERIOUS_PYTHON_WINDIR "$ENV{WINDIR}")
set(serious_python_windows_bundled_libraries
  "${PYTHON_PACKAGE}/python${PYTHON_VERSION_NODOT}$<$<CONFIG:Debug>:_d>.dll"
  "${PYTHON_PACKAGE}/python3$<$<CONFIG:Debug>:_d>.dll"
  "$<IF:$<CONFIG:Debug>,${DART_BRIDGE_DEBUG_DLL},${DART_BRIDGE_RELEASE_DLL}>"
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
  COMMAND IF \"$<$<CONFIG:Release>:release>\" == \"release\" DEL \"${CMAKE_BINARY_DIR}/runner/Release/DLLs\\*_d.*\" /S /Q
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
