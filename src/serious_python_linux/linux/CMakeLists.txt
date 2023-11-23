# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# sudo apt install libstdc++-12-dev
# https://askubuntu.com/questions/829310/how-to-upgrade-cmake-in-ubuntu

# Project-level configuration.
set(PROJECT_NAME "serious_python_linux")
set(GITHUB_RELEASE_DATE "20231002")
set(PYTHON_VERSION "3.11.6")
set(PYTHON_ARCH ${CMAKE_HOST_SYSTEM_PROCESSOR})
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "serious_python_linux_plugin")

set(PYTHON_PACKAGE ${CMAKE_BINARY_DIR}/python)
set(PYTHON_URL https://github.com/indygreg/python-build-standalone/releases/download/${GITHUB_RELEASE_DATE}/cpython-${PYTHON_VERSION}+${GITHUB_RELEASE_DATE}-${PYTHON_ARCH}-unknown-linux-gnu-install_only.tar.gz)
set(PYTHON_FILE ${CMAKE_BINARY_DIR}/cpython-${PYTHON_VERSION}+${GITHUB_RELEASE_DATE}-${PYTHON_ARCH}-unknown-linux-gnu-install_only.tar.gz)
if (NOT EXISTS ${PYTHON_FILE})
  file(DOWNLOAD ${PYTHON_URL} ${PYTHON_FILE})
  file(ARCHIVE_EXTRACT INPUT ${PYTHON_FILE} DESTINATION ${CMAKE_BINARY_DIR})
endif()

add_custom_target(OPTIMIZE_PYTHON_DIST ALL)
add_custom_command(TARGET OPTIMIZE_PYTHON_DIST PRE_BUILD
  COMMAND "${PYTHON_PACKAGE}/bin/python3" -m compileall -b .
  COMMAND rm -rf `find . -type d -name __pycache__`
  COMMAND find . -name \"*.py\" -type f -delete
  WORKING_DIRECTORY "${PYTHON_PACKAGE}/lib/python3.11"
)

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "serious_python_linux_plugin.cc"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
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
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
include_directories(
  "${PYTHON_PACKAGE}/include/python3.11"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  "${PYTHON_PACKAGE}/lib/libpython3.so"
)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(serious_python_linux_bundled_libraries
  "${PYTHON_PACKAGE}/lib/libpython3.so"
  "${PYTHON_PACKAGE}/lib/libpython3.11.so.1.0"
  PARENT_SCOPE
)

install(DIRECTORY "${PYTHON_PACKAGE}/lib/python3.11"
  DESTINATION "${CMAKE_BINARY_DIR}/bundle")