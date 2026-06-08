#ifndef SeriousPythonBridgePlugin_h
#define SeriousPythonBridgePlugin_h

#include <Python.h>

// Defined in ../native/dart_bridge.c. Declared here so the Swift plugin code
// can pass it to SeriousPython.registerPythonExtension(name:initFn:) via the
// auto-generated Clang module map for this pod.
PyObject* PyInit_dart_bridge(void);

#endif
