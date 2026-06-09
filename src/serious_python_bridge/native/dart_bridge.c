#define PY_SSIZE_T_CLEAN
// Build against the CPython Limited API so a single compiled .so works across
// all Python 3.12+ minor versions (abi3 stable ABI). Every Py* symbol used
// below is in the Limited API since 3.2 (3.4 for PyGILState_*).
#define Py_LIMITED_API 0x030c0000
#include <Python.h>
#include <stdint.h>
#include <stdio.h>
#include "dart_api/dart_api_dl.h"

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

// ---------------------------------------------------------------------------
// Core: symbols called from Dart via FFI plus exported helpers the Python-side
// shim (dart_bridge_shim.c) resolves at runtime via dlsym. Compiled into
// libflet_bridge.{so,dll,dylib} by the Flutter plugin build. On Apple
// platforms also compiled into the static archive linked into the
// serious_python framework alongside dart_bridge_shim.c.
//
// The shim NEVER defines its own copy of these symbols — it always looks them
// up at runtime. That keeps Dart's view of `global_enqueue_handler_func` and
// the Python shim's view as a single shared cell on every platform.
// ---------------------------------------------------------------------------

// Exported (non-static) so dart_bridge_shim.c's set_enqueue_handler_func can
// write to it via dlsym. Initialised to NULL; the shim swaps in a PyObject*
// callable when Python registers a handler.
EXPORT PyObject* dart_bridge_global_enqueue_handler_func = NULL;

EXPORT intptr_t DartBridge_InitDartApiDL(void* data) {
    return Dart_InitializeApiDL(data);
}

EXPORT void DartBridge_EnqueueMessage(const char* data, size_t len) {
    // Drop messages sent before Python has finished Py_Initialize. Acquiring
    // the GIL against an uninitialized interpreter triggers a fatal
    // PyMUTEX_LOCK failure (the gil->mutex is uninitialized). Dart's retry
    // loop will resend until Python is up.
    if (!Py_IsInitialized()) {
        return;
    }

    PyGILState_STATE gstate = PyGILState_Ensure();

    if (!dart_bridge_global_enqueue_handler_func) {
        fprintf(stderr, "[dart_bridge] enqueue handler is not registered\n");
        PyGILState_Release(gstate);
        return;
    }

    PyObject* arg = PyBytes_FromStringAndSize(data, len);
    if (!arg) {
        PyErr_Print();
        PyGILState_Release(gstate);
        return;
    }

    PyObject* result = PyObject_CallFunctionObjArgs(
        dart_bridge_global_enqueue_handler_func, arg, NULL);
    if (!result) {
        PyErr_Print();
    }

    Py_XDECREF(arg);
    Py_XDECREF(result);
    PyGILState_Release(gstate);
}

// Exported helper called by the shim's send_bytes(). Keeps the
// Dart_PostCObject_DL invocation in this translation unit so the shim doesn't
// need its own copy of dart_api_dl.c. Returns 0 on success, -1 on failure with
// a Python exception set.
EXPORT int dart_bridge_post_to_dart(int64_t port, const char* buffer, size_t length) {
    if (port == 0) {
        PyErr_SetString(PyExc_RuntimeError, "Dart port is 0 (invalid)");
        return -1;
    }

    // Dart_PostCObject_DL is a function pointer populated by Dart_InitializeApiDL.
    // Calling it before init segfaults; surface a clean error instead.
    if (Dart_PostCObject_DL == NULL) {
        PyErr_SetString(PyExc_RuntimeError,
                        "Dart API DL not initialized (call DartBridge_InitDartApiDL from Dart first)");
        return -1;
    }

    Dart_CObject obj;
    obj.type = Dart_CObject_kTypedData;
    obj.value.as_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_typed_data.length = (int32_t)length;
    obj.value.as_typed_data.values = (void*)buffer;

    if (!Dart_PostCObject_DL(port, &obj)) {
        PyErr_SetString(PyExc_RuntimeError, "Dart_PostCObject_DL failed");
        return -1;
    }
    return 0;
}
