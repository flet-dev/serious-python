# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "serious_python_windows")
set(PYTHON_VERSION "3.10.11")
project(${PROJECT_NAME} LANGUAGES CXX)

# https://stackoverflow.com/questions/34799916/copy-file-from-source-directory-to-binary-directory-using-cmake
# https://stackoverflow.com/questions/46995733/how-to-set-cmake-in-order-to-add-txt-files-into-working-directory-as-resource

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "serious_python_windows_plugin")

set(NUGET_URL https://dist.nuget.org/win-x86-commandline/latest/nuget.exe)
set(NUGET ${CMAKE_BINARY_DIR}/nuget.exe)
if (NOT EXISTS ${NUGET})
  file(DOWNLOAD ${NUGET_URL} ${NUGET})
endif()

set(PACKAGES ${CMAKE_BINARY_DIR}/packages)
set(PYTHON_PACKAGE ${PACKAGES}/python)
if (NOT EXISTS ${PYTHON_PACKAGE})
  add_custom_target(PYTHON_PACKAGE_DOWNLOAD ALL)
  add_custom_command(
    TARGET PYTHON_PACKAGE_DOWNLOAD PRE_BUILD
    COMMAND ${NUGET} install python -Version ${PYTHON_VERSION} -ExcludeVersion -OutputDirectory ${PACKAGES}
    COMMAND ${CMAKE_COMMAND} -E copy
      "${PYTHON_PACKAGE}/tools/libs/python310.lib"
      "${PYTHON_PACKAGE}/tools/libs/python310_d.lib"
    DEPENDS ${NUGET}
  )
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

set_target_properties(
  ${PLUGIN_NAME} PROPERTIES
  VS_PROJECT_IMPORT ${PYTHON_PACKAGE}/build/native/python.props
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

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
set(serious_python_windows_bundled_libraries
  "${PYTHON_PACKAGE}/tools/python310.dll"
  "${PYTHON_PACKAGE}/tools/python3.dll"
  "$ENV{WINDIR}/system32/msvcp140.dll"
  "$ENV{WINDIR}/system32/vcruntime140.dll"
  "$ENV{WINDIR}/system32/vcruntime140_1.dll"
  PARENT_SCOPE
)

# Copy Python libraries
add_custom_target(CopyPythonDLLs ALL DEPENDS PYTHON_PACKAGE_DOWNLOAD)
add_custom_command(TARGET CopyPythonDLLs POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>"
  COMMAND ${CMAKE_COMMAND} -E copy_directory 
    "${PYTHON_PACKAGE}/tools/Lib"
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/Lib"
  COMMAND ${CMAKE_COMMAND} -E copy_directory 
    "${PYTHON_PACKAGE}/tools/DLLs"
    "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>/DLLs"
)