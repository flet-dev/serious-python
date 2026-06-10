# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# sudo apt install libstdc++-12-dev
# https://askubuntu.com/questions/829310/how-to-upgrade-cmake-in-ubuntu

# Project-level configuration.
set(PROJECT_NAME "serious_python_linux")
if(DEFINED ENV{SERIOUS_PYTHON_VERSION})
  set(PYTHON_VERSION "$ENV{SERIOUS_PYTHON_VERSION}")
else()
  set(PYTHON_VERSION "3.14")
endif()
set(PYTHON_ARCH ${CMAKE_HOST_SYSTEM_PROCESSOR})
if(DEFINED ENV{DART_BRIDGE_VERSION})
  set(DART_BRIDGE_VERSION "$ENV{DART_BRIDGE_VERSION}")
else()
  set(DART_BRIDGE_VERSION "1.2.2")
endif()
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "serious_python_linux_plugin")

# ---- python-linux-dart tarball (libpython + stdlib) -----------------------
set(PYTHON_PACKAGE ${CMAKE_BINARY_DIR}/python)
set(PYTHON_URL https://github.com/flet-dev/python-build/releases/download/v${PYTHON_VERSION}/python-linux-dart-${PYTHON_VERSION}-${PYTHON_ARCH}.tar.gz)
set(PYTHON_FILE ${CMAKE_BINARY_DIR}/python-linux-dart-${PYTHON_VERSION}-${PYTHON_ARCH}.tar.gz)
if (NOT EXISTS ${PYTHON_FILE})
  file(DOWNLOAD ${PYTHON_URL} ${PYTHON_FILE})
  file(ARCHIVE_EXTRACT INPUT ${PYTHON_FILE} DESTINATION ${CMAKE_BINARY_DIR}/python)
endif()

# ---- dart_bridge prebuilt .so ---------------------------------------------
# abi3-linked against libpython3.so (the runtime linker finds libpython3.so
# next to the consuming app's exe; the python-linux-dart tarball above
# provides it).
set(DART_BRIDGE_SO ${CMAKE_BINARY_DIR}/dart_bridge/libdart_bridge.so)
if(NOT EXISTS "${DART_BRIDGE_SO}")
  file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/dart_bridge)
  file(DOWNLOAD
    "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/libdart_bridge-linux-${PYTHON_ARCH}.so"
    "${DART_BRIDGE_SO}"
    STATUS _dl_status SHOW_PROGRESS)
  list(GET _dl_status 0 _dl_code)
  list(GET _dl_status 1 _dl_message)
  if(NOT _dl_code EQUAL 0)
    file(REMOVE "${DART_BRIDGE_SO}")
    message(FATAL_ERROR "Failed to download libdart_bridge: ${_dl_message}")
  endif()
endif()

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

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# List of absolute paths to libraries that should be bundled with the plugin.
# Includes libdart_bridge.so (downloaded above) so Flutter copies it into the
# runner's lib/ dir; libpython3.so + libpython<ver>.so.1.0 from the python-
# linux-dart tarball so dart_bridge's DT_NEEDED libpython3.so resolves at
# runtime to the abi3 stub which forwards to the version-specific lib.
set(serious_python_linux_bundled_libraries
  "${DART_BRIDGE_SO}"
  "${PYTHON_PACKAGE}/lib/libpython3.so"
  "${PYTHON_PACKAGE}/lib/libpython${PYTHON_VERSION}.so.1.0"
  PARENT_SCOPE
)

install(DIRECTORY "${PYTHON_PACKAGE}/lib/python${PYTHON_VERSION}"
  DESTINATION "${CMAKE_BINARY_DIR}/bundle")

# Mirror an external site-packages dir into the bundle if the env var is set
# AND points at an existing directory. The env var may be set workflow-wide
# while specific jobs don't actually create the directory.
if(DEFINED ENV{SERIOUS_PYTHON_SITE_PACKAGES} AND EXISTS "$ENV{SERIOUS_PYTHON_SITE_PACKAGES}")
  install(CODE "
    file(REMOVE_RECURSE \"${CMAKE_BINARY_DIR}/bundle/site-packages\")
    file(MAKE_DIRECTORY \"${CMAKE_BINARY_DIR}/bundle/site-packages\")
    file(COPY \"$ENV{SERIOUS_PYTHON_SITE_PACKAGES}/\" DESTINATION \"${CMAKE_BINARY_DIR}/bundle/site-packages\")
  ")
endif()
