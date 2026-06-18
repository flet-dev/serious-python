# Helper invoked by CMakeLists.txt's CopyPythonDLLs target.
# Removes files matching semicolon-separated -DGLOBS=... under -DDIR=...
# without failing if the glob has no matches.

if(NOT DEFINED DIR OR NOT DEFINED GLOBS)
  message(FATAL_ERROR "rm_globs.cmake requires -DDIR and -DGLOBS")
endif()

foreach(_pattern IN LISTS GLOBS)
  file(GLOB _matches "${DIR}/${_pattern}")
  if(_matches)
    file(REMOVE ${_matches})
  endif()
endforeach()
