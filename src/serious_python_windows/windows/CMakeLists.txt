# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "serious_python_windows")
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
if(PYTHON_FULL_VERSION STREQUAL "")
  message(FATAL_ERROR "serious_python: unknown SERIOUS_PYTHON_VERSION '${PYTHON_VERSION}'")
endif()
string(REPLACE "." "" PYTHON_VERSION_NODOT "${PYTHON_VERSION}")
if(DEFINED ENV{DART_BRIDGE_VERSION})
  set(DART_BRIDGE_VERSION "$ENV{DART_BRIDGE_VERSION}")
else()
  pv_get("dart_bridge_version" DART_BRIDGE_VERSION)
endif()

# Cross-plugin download cache. FLET_CACHE_DIR is the same env var used by the
# Android gradle task and the prepare_*.sh scripts on Darwin; defaulting to
# ~/.flet/cache (%USERPROFILE%\.flet\cache on Windows) keeps a single shared
# location across all plugins. Files land in versioned subdirs so a Python
# or dart_bridge version bump pulls a fresh artifact without invalidating the
# others.
if(DEFINED ENV{FLET_CACHE_DIR})
  set(FLET_CACHE_DIR "$ENV{FLET_CACHE_DIR}")
elseif(DEFINED ENV{USERPROFILE})
  set(FLET_CACHE_DIR "$ENV{USERPROFILE}/.flet/cache")
else()
  set(FLET_CACHE_DIR "$ENV{HOME}/.flet/cache")
endif()
# Date-keyed so a same-version re-release (new build date) re-downloads instead
# of being served stale from a previous release's cache. dart-bridge stays
# version-keyed (its re-releases bump the version).
set(PB_CACHE "${FLET_CACHE_DIR}/python-build/v${PYTHON_FULL_VERSION}-${PYTHON_BUILD_DATE}")
set(DB_CACHE "${FLET_CACHE_DIR}/dart-bridge/v${DART_BRIDGE_VERSION}")
file(MAKE_DIRECTORY "${PB_CACHE}" "${DB_CACHE}")

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
set(PYTHON_URL "https://github.com/flet-dev/python-build/releases/download/${PYTHON_BUILD_DATE}/python-windows-for-dart-${PYTHON_FULL_VERSION}.zip")
# Tarball lives in the shared cache; extraction targets the per-plugin build
# tree so a `flutter clean` doesn't force a re-download.
set(PYTHON_FILE "${PB_CACHE}/python-windows-for-dart-${PYTHON_FULL_VERSION}.zip")

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

_sp_download("${PYTHON_URL}" "${PYTHON_FILE}")
# Re-extract when the tree is missing OR was unpacked for a different
# version/release (a marker keyed to version + build date), so a same-version
# re-release replaces it instead of being skipped.
set(_py_build_id "${PYTHON_FULL_VERSION}-${PYTHON_BUILD_DATE}")
set(_py_marker "${PYTHON_PACKAGE}/.python_build_id")
set(_py_extract TRUE)
if(EXISTS "${_py_marker}")
  file(READ "${_py_marker}" _py_cur)
  string(STRIP "${_py_cur}" _py_cur)
  if(_py_cur STREQUAL "${_py_build_id}")
    set(_py_extract FALSE)
  endif()
endif()
if(_py_extract)
  file(REMOVE_RECURSE "${PYTHON_PACKAGE}")
  file(ARCHIVE_EXTRACT INPUT "${PYTHON_FILE}" DESTINATION "${PYTHON_PACKAGE}")
  file(WRITE "${_py_marker}" "${_py_build_id}")
endif()

# ---- dart_bridge prebuilt DLLs --------------------------------------------
# Release CRT (.dll) is what Release Flutter builds consume; Debug CRT
# (_d.dll) is what `fvm flutter run` / Debug builds consume. Both ship in
# every release of flet-dev/dart-bridge; we bundle both and let Flutter's
# CONFIG-aware copy machinery pick the right one at app launch time.
#
# Cached under the upstream arch-qualified filenames so multiple flet-dev/
# dart-bridge versions can coexist in $FLET_CACHE_DIR. Copied to stable
# unqualified names in the build tree because Flutter's bundled_libraries
# machinery preserves filenames as-is, and the Dart side opens the DLL by
# `dart_bridge[_d].dll` (no arch suffix).
set(DART_BRIDGE_RELEASE_CACHED "${DB_CACHE}/dart_bridge-windows-x86_64.dll")
set(DART_BRIDGE_DEBUG_CACHED   "${DB_CACHE}/dart_bridge_d-windows-x86_64.dll")

_sp_download(
  "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/dart_bridge-windows-x86_64.dll"
  "${DART_BRIDGE_RELEASE_CACHED}")
_sp_download(
  "https://github.com/flet-dev/dart-bridge/releases/download/v${DART_BRIDGE_VERSION}/dart_bridge_d-windows-x86_64.dll"
  "${DART_BRIDGE_DEBUG_CACHED}")

set(DART_BRIDGE_DIR "${CMAKE_BINARY_DIR}/dart_bridge")
set(DART_BRIDGE_RELEASE_DLL "${DART_BRIDGE_DIR}/dart_bridge.dll")
set(DART_BRIDGE_DEBUG_DLL   "${DART_BRIDGE_DIR}/dart_bridge_d.dll")
file(MAKE_DIRECTORY "${DART_BRIDGE_DIR}")
configure_file("${DART_BRIDGE_RELEASE_CACHED}" "${DART_BRIDGE_RELEASE_DLL}" COPYONLY)
configure_file("${DART_BRIDGE_DEBUG_CACHED}"   "${DART_BRIDGE_DEBUG_DLL}"   COPYONLY)

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

# Copy Python libraries.
#
# Replaced the prior cmd.exe `DEL` invocations with `cmake -E rm -f --` which
# is forgiving about missing globs / missing files. MSBuild's CustomBuild
# wrapper treats any non-zero exit code as a hard failure, and `DEL <missing>`
# returns 1, which made the whole CopyPythonDLLs target fragile.
set(SP_RUNNER_OUT "${CMAKE_BINARY_DIR}/runner/$<$<CONFIG:Release>:Release>$<$<CONFIG:Debug>:Debug>")
add_custom_target(CopyPythonDLLs ALL)
add_custom_command(TARGET CopyPythonDLLs POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory   "${SP_RUNNER_OUT}"
  COMMAND ${CMAKE_COMMAND} -E copy_directory   "${PYTHON_PACKAGE}/Lib"  "${SP_RUNNER_OUT}/Lib"
  COMMAND ${CMAKE_COMMAND} -E copy_directory   "${PYTHON_PACKAGE}/DLLs" "${SP_RUNNER_OUT}/DLLs"
  # Strip Debug-only PYDs from Release builds (best effort — missing files OK).
  COMMAND ${CMAKE_COMMAND} -E rm -f --
    "${SP_RUNNER_OUT}/DLLs/tcl86t.dll"
    "${SP_RUNNER_OUT}/DLLs/tk86t.dll"
  COMMAND ${CMAKE_COMMAND} -DDIR=${SP_RUNNER_OUT}/DLLs -DGLOBS=*.ico\;*.cat
    -P "${CMAKE_CURRENT_SOURCE_DIR}/rm_globs.cmake"
)

# Mirror the user's external site-packages dir into runner/site-packages if
# the env var is set AND points at an existing directory. (The CI env var
# may be set workflow-wide while specific jobs don't actually create the
# directory — `cmake -E copy_directory` against a missing source fails,
# which used to wedge CopyPythonDLLs.)
if(DEFINED ENV{SERIOUS_PYTHON_SITE_PACKAGES} AND EXISTS "$ENV{SERIOUS_PYTHON_SITE_PACKAGES}")
  add_custom_command(TARGET CopyPythonDLLs POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${SP_RUNNER_OUT}/site-packages"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SP_RUNNER_OUT}/site-packages"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "$ENV{SERIOUS_PYTHON_SITE_PACKAGES}"
      "${SP_RUNNER_OUT}/site-packages"
  )
endif()

# The app's Python sources (staged unpacked by serious_python's `package`
# command) ship as a bare `app/` dir next to the bundled CPython Lib/DLLs/
# site-packages; the runtime adds `<exeDir>/app` to sys.path (no extraction).
if(DEFINED ENV{SERIOUS_PYTHON_APP} AND EXISTS "$ENV{SERIOUS_PYTHON_APP}")
  add_custom_command(TARGET CopyPythonDLLs POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${SP_RUNNER_OUT}/app"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SP_RUNNER_OUT}/app"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "$ENV{SERIOUS_PYTHON_APP}"
      "${SP_RUNNER_OUT}/app"
  )
endif()
