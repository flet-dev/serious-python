// Python-callable shim for the dart_bridge module.
//
// This file is the *only* source compiled into the dart_bridge wheel built by
// cibuildwheel. It contains no Dart-callable symbols and no copy of the
// shared `dart_bridge_global_enqueue_handler_func` cell — instead it resolves
// the core's exports (defined in dart_bridge.c, linked into libflet_bridge)
// at PyInit time via dlsym/GetProcAddress. That keeps Dart's view and
// Python's view of the global as the SAME cell on Linux/Windows/Android.
//
// On Apple platforms this same file is also static-linked into the
// serious_python framework alongside dart_bridge.c — the runtime lookup
// then resolves to the symbols statically linked into the host binary
// (dlopen of libflet_bridge is skipped because there's no such file).

#define PY_SSIZE_T_CLEAN
#define Py_LIMITED_API 0x030c0000
#include <Python.h>
#include <stdint.h>
#include <stdio.h>

#include <stdarg.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

// Function-pointer + global types resolved at PyInit time.
typedef int (*PostToDartFn)(int64_t port, const char* buffer, size_t length);

static PyObject** g_handler_slot = NULL;   // points at dart_bridge_global_enqueue_handler_func in libflet_bridge
static PostToDartFn g_post_to_dart = NULL; // dart_bridge_post_to_dart in libflet_bridge

#if defined(_WIN32)
#include <string.h>

// Diagnostic log file — Python's stderr is not captured by flutter test on
// Windows, so we tee the shim's progress to a known absolute path the
// workflow can dump after the test fails.
static void shim_log(const char* fmt, ...) {
    char path[MAX_PATH];
    DWORD n = GetTempPathA(MAX_PATH, path);
    if (n == 0 || n + 25 > MAX_PATH) return;
    strcat(path, "dart_bridge_shim.log");
    FILE* f = fopen(path, "a");
    if (!f) return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fclose(f);
}

// Marker call so we can detect whether PyInit ran at all (helps distinguish
// "PyInit ran but flet_bridge.dll lookup failed" from "PyInit never ran
// because the .pyd failed to load").
static void shim_log_init(const char* phase) {
    char path[MAX_PATH];
    DWORD n = GetTempPathA(MAX_PATH, path);
    if (n == 0 || n + 25 > MAX_PATH) return;
    strcat(path, "dart_bridge_shim.log");
    FILE* f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "[shim] === %s ===\n", phase);
    fclose(f);
}

static HMODULE shim_find_flet_bridge_module(void) {
    // 1. GetModuleHandleA looks at modules already loaded into the process
    //    (e.g. by Dart's DynamicLibrary.open). Returns NULL without loading
    //    anything if not already mapped.
    HMODULE flet = GetModuleHandleA("flet_bridge.dll");
    if (flet) {
        shim_log("[shim] GetModuleHandleA(flet_bridge.dll) -> %p\n", (void*)flet);
        return flet;
    }
    shim_log("[shim] GetModuleHandleA(flet_bridge.dll) -> NULL (err=%lu)\n",
             (unsigned long)GetLastError());

    // 2. LoadLibraryA with default DLL search. Reaches the calling module's
    //    directory (dart_bridge.pyd's dir) + system paths + PATH.
    flet = LoadLibraryA("flet_bridge.dll");
    if (flet) {
        shim_log("[shim] LoadLibraryA(flet_bridge.dll) -> %p\n", (void*)flet);
        return flet;
    }
    shim_log("[shim] LoadLibraryA(flet_bridge.dll) -> NULL (err=%lu)\n",
             (unsigned long)GetLastError());

    // 3. Construct an absolute path next to the running .exe (where Flutter
    //    places plugin DLLs) and try that.
    char exePath[MAX_PATH];
    DWORD len = GetModuleFileNameA(NULL, exePath, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        shim_log("[shim] GetModuleFileNameA failed (len=%lu)\n", (unsigned long)len);
        return NULL;
    }
    for (DWORD i = len; i > 0; i--) {
        if (exePath[i - 1] == '\\' || exePath[i - 1] == '/') {
            exePath[i] = '\0';
            break;
        }
    }
    if (strlen(exePath) + strlen("flet_bridge.dll") + 1 >= MAX_PATH) return NULL;
    strcat(exePath, "flet_bridge.dll");
    shim_log("[shim] trying absolute path: %s\n", exePath);
    flet = LoadLibraryA(exePath);
    if (!flet) {
        shim_log("[shim] LoadLibraryA(absolute) -> NULL (err=%lu)\n",
                 (unsigned long)GetLastError());
    } else {
        shim_log("[shim] LoadLibraryA(absolute) -> %p\n", (void*)flet);
    }
    return flet;
}

static void* shim_sym_lookup(const char* name) {
    HMODULE flet = shim_find_flet_bridge_module();
    if (!flet) {
        shim_log("[shim] flet_bridge.dll not found anywhere\n");
        return NULL;
    }
    void* p = (void*)GetProcAddress(flet, name);
    if (!p) {
        shim_log("[shim] GetProcAddress(%s) -> NULL (err=%lu)\n", name,
                 (unsigned long)GetLastError());
    } else {
        shim_log("[shim] GetProcAddress(%s) -> %p\n", name, p);
    }
    return p;
}
#else
static void* shim_sym_lookup(const char* name) {
    // RTLD_DEFAULT searches every library already loaded into the process
    // including ones loaded with RTLD_LOCAL by Dart's DynamicLibrary.open.
    void* p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    // Not visible globally (Dart loaded libflet_bridge with RTLD_LOCAL). Try
    // an explicit RTLD_GLOBAL dlopen so subsequent lookups see it. dlopen of
    // an already-loaded library returns the existing handle — single instance,
    // same memory, just promoted into the global namespace.
#if defined(__APPLE__)
    void* h = dlopen("libflet_bridge.dylib", RTLD_NOW | RTLD_GLOBAL);
#else
    void* h = dlopen("libflet_bridge.so", RTLD_NOW | RTLD_GLOBAL);
#endif
    if (!h) return NULL;
    return dlsym(h, name);
}
#endif

static PyObject* set_enqueue_handler_func(PyObject* self, PyObject* args) {
    PyObject* func;

    if (!PyArg_ParseTuple(args, "O:set_enqueue_handler_func", &func)) {
        return NULL;
    }
    if (!PyCallable_Check(func)) {
        PyErr_SetString(PyExc_TypeError, "parameter must be callable");
        return NULL;
    }
    if (!g_handler_slot) {
        PyErr_SetString(PyExc_RuntimeError,
                        "dart_bridge: libflet_bridge symbol not resolved (was the bridge plugin loaded?)");
        return NULL;
    }

    Py_XINCREF(func);
    Py_XDECREF(*g_handler_slot);
    *g_handler_slot = func;

    Py_RETURN_NONE;
}

static PyObject* send_bytes(PyObject* self, PyObject* args) {
    int64_t port;
    const char* buffer;
    Py_ssize_t length;

    if (!PyArg_ParseTuple(args, "Ly#", &port, &buffer, &length)) {
        return NULL;
    }
    if (!g_post_to_dart) {
        PyErr_SetString(PyExc_RuntimeError,
                        "dart_bridge: libflet_bridge symbol not resolved (was the bridge plugin loaded?)");
        return NULL;
    }
    if (g_post_to_dart(port, buffer, (size_t)length) != 0) {
        // Helper sets the exception.
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
#if defined(_WIN32)
    shim_log_init("PyInit_dart_bridge entered");
#endif
    // Resolve the libflet_bridge exports we depend on. Surface a clean
    // ImportError if the lookup fails — typically means the bridge plugin's
    // native library wasn't loaded into the process before Python ran.
    g_handler_slot = (PyObject**)shim_sym_lookup("dart_bridge_global_enqueue_handler_func");
    g_post_to_dart = (PostToDartFn)shim_sym_lookup("dart_bridge_post_to_dart");
    if (!g_handler_slot || !g_post_to_dart) {
        PyErr_SetString(PyExc_ImportError,
                        "dart_bridge: failed to resolve libflet_bridge symbols "
                        "(is serious_python_bridge's native library loaded into the process?)");
        return NULL;
    }
    return PyModule_Create(&moduledef);
}
