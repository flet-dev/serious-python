cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "serious_python_bridge")
project(${PROJECT_NAME} LANGUAGES C)

# Python headers + libpython3.so come from the python-android-dart tarball
# that build.gradle's preparePythonDist task extracted into
# build/python-dist/${ANDROID_ABI}/. We link against libpython at build time
# so Android's strict dynamic linker accepts the .so on load; at runtime the
# linker resolves libpython3.so against the copy serious_python_android
# already shipped in the same jniLibs/${ANDROID_ABI}/ directory.
set(PYTHON_DIST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/python-dist/${ANDROID_ABI}")
set(FLET_BRIDGE_PYTHON_INCLUDE_DIRS "${PYTHON_DIST_DIR}/include/python${PYTHON_VERSION}")
set(FLET_BRIDGE_PYTHON_LIBRARIES "${PYTHON_DIST_DIR}/lib/libpython3.so")

add_subdirectory("../native" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Android 15: 16 KB page size support.
set_target_properties(flet_bridge PROPERTIES
  LINK_FLAGS "-Wl,-z,max-page-size=16384"
)

set(serious_python_bridge_bundled_libraries
  $<TARGET_FILE:flet_bridge>
  PARENT_SCOPE
)
