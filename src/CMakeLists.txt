# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(serious_python_library VERSION 0.0.1 LANGUAGES C)

add_library(serious_python SHARED
  "serious_python.c"
)

set_target_properties(serious_python PROPERTIES
  PUBLIC_HEADER serious_python.h
  OUTPUT_NAME "serious_python"
)

target_compile_definitions(serious_python PUBLIC DART_SHARED_LIB)
