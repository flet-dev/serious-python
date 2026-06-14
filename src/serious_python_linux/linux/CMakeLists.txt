# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# sudo apt install libstdc++-12-dev
# https://askubuntu.com/questions/829310/how-to-upgrade-cmake-in-ubuntu

# Project-level configuration.
set(PROJECT_NAME "serious_python_linux")
# Python runtime versions come from the generated python_versions.properties
# (a snapshot of python-build's manifest.json — see serious_python's
# gen_version_tables). SERIOUS_PYTHON_VERSION selects the version; the rest
# derive from the table. The per-field env vars are escape hatches.
set(_PV_FILE "${CMAKE_CURRENT_LIST_DIR}/python_versions.properties")
function(pv_get key out)
  string(REPLACE "." "\\." _re "${key}")
  file(STRINGS "${_PV_FILE}" _m REGEX "^${_re}=")
  if(_m)
    string(REGEX REPLACE "^[^=]*=" "" _v "${_m}")
    set(${out} "${_v}" PARENT_SCOPE)
  else()
    set(${out} "" PARENT_SCOPE)
  endif()
endfunction()

if(DEFINED ENV{SERIOUS_PYTHON_VERSION})
  set(PYTHON_VERSION "$ENV{SERIOUS_PYTHON_VERSION}")
else()
  pv_get("default_python_version" PYTHON_VERSION)
endif()
if(DEFINED ENV{SERIOUS_PYTHON_FULL_VERSION})
  set(PYTHON_FULL_VERSION "$ENV{SERIOUS_PYTHON_FULL_VERSION}")
else()
  pv_get("${PYTHON_VERSION}.full_version" PYTHON_FULL_VERSION)
endif()
if(DEFINED ENV{SERIOUS_PYTHON_BUILD_DATE})
  set(PYTHON_BUILD_DATE "$ENV{SERIOUS_PYTHON_BUILD_DATE}")
else()
  pv_get("python_build_release_date" PYTHON_BUILD_DATE)
endif()
set(PYTHON_ARCH ${CMAKE_HOST_SYSTEM_PROCESSOR})
if(DEFINED ENV{DART_BRIDGE_VERSION})
  set(DART_BRIDGE_VERSION "$ENV{DART_BRIDGE_VERSION}")
else()
  pv_get("dart_bridge_version" DART_BRIDGE_VERSION)
endif()
if(PYTHON_FULL_VERSION STREQUAL "")
  message(FATAL_ERROR "serious_python: unknown SERIOUS_PYTHON_VERSION '${PYTHON_VERSION}'")
endif()

# Cross-plugin download cache. FLET_CACHE_DIR is the same env var used by the
# Android gradle task, the Darwin prepare_*.sh scripts, and Windows
# CMakeLists; defaulting to ~/.flet/cache keeps a single shared location.
if(DEFINED ENV{FLET_CACHE_DIR})
  set(FLET_CACHE_DIR "$ENV{FLET_CACHE_DIR}")
else()
  set(FLET_CACHE_DIR "$ENV{HOME}/.flet/cache")
endif()
set(PB_CACHE "${FLET_CACHE_DIR}/python-build/v${PYTHON_FULL_VERSION}")
set(DB_CACHE "${FLET_CACHE_DIR}/dart-bridge/v${DART_BRIDGE_VERSION}")
file(MAKE_DIRECTORY "${PB_CACHE}" "${DB_CACHE}")

project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "serious_python_linux_plugin")

function(_sp_download url dest)
  if(EXISTS "${dest}")
    return()
  endif()
  message(STATUS "Downloading: ${url}")
  # .tmp + rename so a Ctrl-C / network blip doesn't poison the cache.
  file(DOWNLOAD "${url}" "${dest}.tmp" STATUS _dl_status SHOW_PROGRESS)
  list(GET _dl_status 0 _dl_code)
  list(GET _dl_status 1 _dl_message)
  if(NOT _dl_code EQUAL 0)
    file(REMOVE "${dest}.tmp")
    message(FATAL_ERROR "Failed to download ${url}: ${_dl_message}")
  endif()
  file(RENAME "${dest}.tmp" "${dest}")
endfunction()

# ---- python-linux-dart tarball (libpython + stdlib) -----------------------
# Tarball lives in the shared cache; extraction targets the per-plugin build
# tree so a `flutter clean` doesn't force a re-download.
set(PYTHON_PACKAGE ${CMAKE_BINARY_DIR}/python)
set(PYTHON_URL https://github.com/flet-dev/python-build/releases/download/${PYTHON_BUILD_DATE}/python-linux-dart-${PYTHON_FULL_VERSION}-${PYTHON_ARCH}.tar.gz)
set(PYTHON_FILE "${PB_CACHE}/python-linux-dart-${PYTHON_FULL_VERSION}-${PYTHON_ARCH}.tar.gz")
_sp_download("${PYTHON_URL}" "${PYTHON_FILE}")
if(NOT EXISTS "${PYTHON_PACKAGE}/lib/libpython3.so")
  file(ARCHIVE_EXTRACT INPUT "${PYTHON_FILE}" DESTINATION "${PYTHON_PACKAGE}")
endif()

# ---- dart_bridge prebuilt .so ---------------------------------------------
# abi3-linked against libpython3.so (the runtime linker finds libpython3.so
# next to the consuming app's exe; the python-linux-dart tarball above
# provides it). Cached under its arch-qualified name so multiple arches can
# co-exist in $FLET_CACHE_DIR; copied to a stable `libdart_bridge.so` in the
# build tree so Flutter's bundled_libraries machinery (and the Dart side's
# DynamicLibrary.open("libdart_bridge.so")) finds a deterministic name.
set(DART_BRIDGE_CACHED "${DB_CACHE}/libdart_bridge-linux-${PYTHON_ARCH}.so")
_sp_download(
  "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/libdart_bridge-linux-${PYTHON_ARCH}.so"
  "${DART_BRIDGE_CACHED}")
set(DART_BRIDGE_SO "${CMAKE_BINARY_DIR}/dart_bridge/libdart_bridge.so")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/dart_bridge")
configure_file("${DART_BRIDGE_CACHED}" "${DART_BRIDGE_SO}" COPYONLY)

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
