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
// Core: symbols called from Dart via FFI. On platforms with the shared-lib
// split these live in libflet_bridge; on iOS they're linked statically into
// the serious_python framework.
// ---------------------------------------------------------------------------

static PyObject* global_enqueue_handler_func = NULL;

EXPORT intptr_t DartBridge_InitDartApiDL(void* data) {
    return Dart_InitializeApiDL(data);
}

EXPORT void DartBridge_EnqueueMessage(const char* data, size_t len) {
    PyGILState_STATE gstate = PyGILState_Ensure();

    if (!global_enqueue_handler_func) {
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

    PyObject* result = PyObject_CallFunctionObjArgs(global_enqueue_handler_func, arg, NULL);
    if (!result) {
        PyErr_Print();
    }

    Py_XDECREF(arg);
    Py_XDECREF(result);
    PyGILState_Release(gstate);
}

// ---------------------------------------------------------------------------
// Shim: Python-callable methods exposed by the `dart_bridge` module.
// ---------------------------------------------------------------------------

static PyObject* set_enqueue_handler_func(PyObject* self, PyObject* args) {
    PyObject* func;

    if (!PyArg_ParseTuple(args, "O:set_enqueue_handler_func", &func)) {
        return NULL;
    }

    if (!PyCallable_Check(func)) {
        PyErr_SetString(PyExc_TypeError, "parameter must be callable");
        return NULL;
    }

    Py_XINCREF(func);
    Py_XDECREF(global_enqueue_handler_func);
    global_enqueue_handler_func = func;

    Py_RETURN_NONE;
}

static PyObject* send_bytes(PyObject* self, PyObject* args) {
    int64_t port;
    const char* buffer;
    Py_ssize_t length;

    if (!PyArg_ParseTuple(args, "Ly#", &port, &buffer, &length)) {
        return NULL;
    }

    if (port == 0) {
        PyErr_SetString(PyExc_RuntimeError, "Dart port is 0 (invalid)");
        return NULL;
    }

    // Dart_PostCObject_DL is a function pointer populated by Dart_InitializeApiDL.
    // Calling it before init segfaults; surface a clean error instead.
    if (Dart_PostCObject_DL == NULL) {
        PyErr_SetString(PyExc_RuntimeError,
                        "Dart API DL not initialized (call DartBridge_InitDartApiDL from Dart first)");
        return NULL;
    }

    Dart_CObject obj;
    obj.type = Dart_CObject_kTypedData;
    obj.value.as_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_typed_data.length = (int32_t)length;
    obj.value.as_typed_data.values = (void*)buffer;

    if (!Dart_PostCObject_DL(port, &obj)) {
        PyErr_SetString(PyExc_RuntimeError, "Dart_PostCObject_DL failed");
        return NULL;
    }

    Py_RETURN_TRUE;
}

static PyMethodDef methods[] = {
    {"send_bytes", send_bytes, METH_VARARGS, "Post a bytes payload to a Dart ReceivePort."},
    {"set_enqueue_handler_func", set_enqueue_handler_func, METH_VARARGS,
     "Register the Python callable that receives bytes posted from Dart."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef moduledef = {
    PyModuleDef_HEAD_INIT,
    "dart_bridge", NULL, -1, methods
};

PyMODINIT_FUNC PyInit_dart_bridge(void) {
    return PyModule_Create(&moduledef);
}
