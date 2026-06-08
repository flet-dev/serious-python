cmake_minimum_required(VERSION 3.15)

set(PROJECT_NAME "serious_python_bridge")
project(${PROJECT_NAME} LANGUAGES C)

cmake_policy(VERSION 3.15...3.25)

add_subdirectory("../native" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Flutter picks up bundled libraries via this variable and copies the file
# alongside the app binary; Dart resolves it via DynamicLibrary.open.
set(serious_python_bridge_bundled_libraries
  $<TARGET_FILE:flet_bridge>
  PARENT_SCOPE
)
