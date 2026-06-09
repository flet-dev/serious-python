cmake_minimum_required(VERSION 3.15)

set(PROJECT_NAME "serious_python_bridge")
project(${PROJECT_NAME} LANGUAGES C)

cmake_policy(VERSION 3.15...3.25)

add_subdirectory("../native" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# python3.dll (the abi3 stable-ABI loader) is what cibuildwheel-built abi3
# wheels — including the dart_bridge.pyd dropped into bundled site-packages —
# import. serious_python_windows only bundles python3_d.dll in Debug builds,
# so Python's import of dart_bridge.pyd fails before PyInit can run with
# "ImportError: DLL load failed". Pull our own python3.dll from the same
# python-windows-for-dart tarball serious_python_windows uses and add it to
# the plugin's bundled_libraries list.
if(DEFINED ENV{SERIOUS_PYTHON_VERSION})
  set(PYTHON_VERSION "$ENV{SERIOUS_PYTHON_VERSION}")
else()
  set(PYTHON_VERSION "3.14")
endif()
set(PYTHON_DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/python_dist)
set(PYTHON_DLL_PATH "${PYTHON_DOWNLOAD_DIR}/python3.dll")
if(NOT EXISTS "${PYTHON_DLL_PATH}")
  set(PYTHON_ZIP "${CMAKE_BINARY_DIR}/python-windows-for-dart-${PYTHON_VERSION}.zip")
  if(NOT EXISTS "${PYTHON_ZIP}")
    file(DOWNLOAD
      "https://github.com/flet-dev/python-build/releases/download/v${PYTHON_VERSION}/python-windows-for-dart-${PYTHON_VERSION}.zip"
      "${PYTHON_ZIP}")
  endif()
  file(MAKE_DIRECTORY "${PYTHON_DOWNLOAD_DIR}")
  file(ARCHIVE_EXTRACT INPUT "${PYTHON_ZIP}"
    DESTINATION "${PYTHON_DOWNLOAD_DIR}"
    PATTERNS "python3.dll")
endif()

# Flutter picks up bundled libraries via this variable and copies the file
# alongside the app binary; Dart resolves it via DynamicLibrary.open.
set(serious_python_bridge_bundled_libraries
  $<TARGET_FILE:flet_bridge>
  "${PYTHON_DLL_PATH}"
  PARENT_SCOPE
)
