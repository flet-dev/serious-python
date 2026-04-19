import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'gen.dart';
import 'log.dart';

export 'gen.dart';

// ----------------------------------------------------------------------
// Global state
// ----------------------------------------------------------------------
CPython? _cpython;
bool _pythonInitialized = false;
Pointer<PyThreadState>? _mainThreadState;
String? _logcatForwardingError;
Future<void> _pythonRunQueue = Future<void>.value();

// ----------------------------------------------------------------------
// Initialization & finalization
// ----------------------------------------------------------------------
void initPythonOnce(String dynamicLibPath) {
  if (_pythonInitialized) return;
  final cpython = getCPython(dynamicLibPath);
  if (cpython.Py_IsInitialized() == 0) {
    spDebug("Initializing Python interpreter...");
    cpython.Py_Initialize();
    if (cpython.Py_IsInitialized() == 0) {
      spDebug("ERROR: Python initialization failed!");
      return;
    }
    // 当前线程（主线程）此时默认持有 GIL
    // 执行重定向脚本（只执行一次）
    final setupError = _setupLogcatForwarding(cpython);
    if (setupError != null) {
      spDebug("Logcat forwarding setup failed: $setupError");
    } else {
      spDebug("Logcat forwarding setup succeeded.");
    }
    // 释放 GIL 并保存主线程状态，允许其他线程获取 GIL
    _mainThreadState = cpython.PyEval_SaveThread();
    _pythonInitialized = true;
    spDebug("Python initialized successfully, GIL released.");
  } else {
    _pythonInitialized = true;
  }
}

void finalizePython() {
  if (!_pythonInitialized) return;
  final cpython = _cpython;
  if (cpython == null) return;
  spDebug("Finalizing Python interpreter...");
  if (_mainThreadState != nullptr) {
    cpython.PyEval_RestoreThread(_mainThreadState!);
    _mainThreadState = nullptr;
  }
  cpython.Py_Finalize();
  _pythonInitialized = false;
  spDebug("Python finalized.");
}

// ----------------------------------------------------------------------
// Queue to serialize Dart calls (optional, but keeps original behavior)
// ----------------------------------------------------------------------
Future<T> _enqueuePythonRun<T>(Future<T> Function() action) {
  final completer = Completer<T>();
  _pythonRunQueue = _pythonRunQueue.then((_) async {
    try {
      completer.complete(await action());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future;
}

// ----------------------------------------------------------------------
// Logcat forwarding (Android only, kept as-is)
// ----------------------------------------------------------------------
const _logcatInitScript = r'''
import logging,sys

if not getattr(sys, "__serious_python_logcat_configured__", False):
    sys.__serious_python_logcat_configured__ = True

    from ctypes import cdll, c_int, c_char_p
    liblog = cdll.LoadLibrary("liblog.so")
    ANDROID_LOG_INFO = 4
    liblog.__android_log_write.argtypes = [c_int, c_char_p, c_char_p]
    liblog.__android_log_write.restype = c_int

    def _log_to_logcat(msg, level=ANDROID_LOG_INFO):
        if not msg:
            return
        if isinstance(msg, bytes):
            msg = msg.decode("utf-8", errors="replace")
        liblog.__android_log_write(level, b"serious_python", msg.encode("utf-8"))

    class _LogcatWriter:
        def write(self, msg):
            _log_to_logcat(msg.strip())
        def flush(self):
            pass

    sys.stdout = sys.stderr = _LogcatWriter()
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(levelname)s %(message)s"))
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.ERROR)
''';

String? _setupLogcatForwarding(CPython cpython) {
  if (_logcatForwardingError != null) return _logcatForwardingError;
  final setupPtr = _logcatInitScript.toNativeUtf8();
  final result = cpython.PyRun_SimpleString(setupPtr.cast<Char>());
  malloc.free(setupPtr);
  if (result != 0) {
    _logcatForwardingError = getPythonError(cpython);
    spDebug("Logcat forwarding setup failed: $_logcatForwardingError");
    return _logcatForwardingError;
  }
  return null;
}

// ----------------------------------------------------------------------
// Core Python execution (assumes GIL already held)
// ----------------------------------------------------------------------
// 这是您需要修改的核心部分
String _runPythonProgramWithGIL(
  String dynamicLibPath,
  String pythonProgramPath,
  String script,
) {
  final cpython = getCPython(dynamicLibPath);
  var result = "";

  if (script.isNotEmpty) {
    // 执行Python代码字符串的逻辑保持不变
    final scriptPtr = script.toNativeUtf8();
    int sr = cpython.PyRun_SimpleString(scriptPtr.cast<Char>());
    malloc.free(scriptPtr);
    if (sr != 0) result = getPythonError(cpython);
  } else {
    // 使用 runpy.run_path() 执行脚本文件
    final runpyModule = cpython.PyImport_ImportModule(
      "runpy".toNativeUtf8().cast<Char>(),
    );
    if (runpyModule == nullptr) {
      return "Error: Failed to import runpy module. ${getPythonError(cpython)}";
    }

    // 获取 runpy.run_path 函数对象
    final runPathFunc = cpython.PyObject_GetAttrString(
      runpyModule,
      "run_path".toNativeUtf8().cast(),
    );
    if (runPathFunc == nullptr) {
      cpython.Py_DecRef(runpyModule);
      return "Error: Failed to get run_path function. ${getPythonError(cpython)}";
    }

    // 准备参数并调用 run_path(your_script_path)
    final scriptPathPtr = pythonProgramPath.toNativeUtf8();
    final args = cpython.PyTuple_New(1);
    cpython.PyTuple_SetItem(
      args,
      0,
      cpython.PyUnicode_FromString(scriptPathPtr.cast<Char>()),
    );
    malloc.free(scriptPathPtr);

    final resultObj = cpython.PyObject_CallObject(runPathFunc, args);
    if (resultObj == nullptr) {
      result = getPythonError(cpython);
    }

    // 清理所有创建的 Python 对象引用
    cpython.Py_DecRef(resultObj);
    cpython.Py_DecRef(args);
    cpython.Py_DecRef(runPathFunc);
    cpython.Py_DecRef(runpyModule);
  }
  return result;
}

// ----------------------------------------------------------------------
// Public API: run Python program/script
// ----------------------------------------------------------------------
CPython getCPython(String dynamicLibPath) {
  return _cpython ??= CPython(DynamicLibrary.open(dynamicLibPath));
}

Future<String> runPythonProgramFFI(
  bool sync,
  String dynamicLibPath,
  String pythonProgramPath,
  String script,
) async {
  // Ensure Python is initialized once (must be called before any GIL usage)
  initPythonOnce(dynamicLibPath);

  return _enqueuePythonRun(() async {
    spDebug(
      "Python run start (sync=$sync, script=${script.isNotEmpty}, program=$pythonProgramPath)",
    );
    final cpython = getCPython(dynamicLibPath);

    if (sync) {
      // Sync: current thread must hold GIL
      final gstate = cpython.PyGILState_Ensure();
      try {
        final result = _runPythonProgramWithGIL(
          dynamicLibPath,
          pythonProgramPath,
          script,
        );
        spDebug("Python run done (resultLength=${result.length})");
        return result;
      } finally {
        cpython.PyGILState_Release(gstate);
      }
    } else {
      // Async: use Isolate.run (new thread). The new thread must acquire GIL itself.
      try {
        final result = await Isolate.run(() {
          final isolateCpython = getCPython(dynamicLibPath);
          final gstate = isolateCpython.PyGILState_Ensure();
          try {
            return _runPythonProgramWithGIL(
              dynamicLibPath,
              pythonProgramPath,
              script,
            );
          } finally {
            isolateCpython.PyGILState_Release(gstate);
          }
        });
        spDebug("Python run done (resultLength=${result.length})");
        return result;
      } catch (e, st) {
        final message = "Dart error running Python: $e\n$st";
        spDebug(message);
        return message;
      }
    }
  });
}

// ----------------------------------------------------------------------
// Error formatting (unchanged from original)
// ----------------------------------------------------------------------
String getPythonError(CPython cpython) {
  final exPtr = cpython.PyErr_GetRaisedException();
  if (exPtr == nullptr) return "Unknown Python error (no exception set).";

  try {
    final formatted = _formatPythonException(cpython, exPtr);
    if (formatted != null && formatted.isNotEmpty) return formatted;

    final fallback = _pyObjectToDartString(cpython, exPtr);
    return fallback ?? "Unknown Python error (failed to stringify exception).";
  } finally {
    cpython.Py_DecRef(exPtr);
    cpython.PyErr_Clear();
  }
}

String? _formatPythonException(
  CPython cpython,
  Pointer<PyObject> exceptionPtr,
) {
  final tracebackModuleNamePtr = "traceback".toNativeUtf8();
  final tracebackModulePtr = cpython.PyImport_ImportModule(
    tracebackModuleNamePtr.cast<Char>(),
  );
  malloc.free(tracebackModuleNamePtr);
  if (tracebackModulePtr == nullptr) return null;

  try {
    final formatFuncNamePtr = "format_exception".toNativeUtf8();
    final formatFuncPtr = cpython.PyObject_GetAttrString(
      tracebackModulePtr,
      formatFuncNamePtr.cast(),
    );
    malloc.free(formatFuncNamePtr);
    if (formatFuncPtr == nullptr) return null;

    try {
      if (cpython.PyCallable_Check(formatFuncPtr) == 0) return null;

      final listPtr = cpython.PyObject_CallOneArg(formatFuncPtr, exceptionPtr);
      if (listPtr == nullptr) return null;

      try {
        final listSize = cpython.PyList_Size(listPtr);
        if (listSize < 0) return null;

        final buffer = StringBuffer();
        for (var i = 0; i < listSize; i++) {
          final itemObj = cpython.PyList_GetItem(listPtr, i);
          if (itemObj == nullptr) continue;

          final line =
              _pyUnicodeToDartString(cpython, itemObj) ??
              _pyObjectToDartString(cpython, itemObj);
          if (line == null) continue;
          buffer.write(line);
        }
        return buffer.toString();
      } finally {
        cpython.Py_DecRef(listPtr);
      }
    } finally {
      cpython.Py_DecRef(formatFuncPtr);
    }
  } finally {
    cpython.Py_DecRef(tracebackModulePtr);
  }
}

String? _pyUnicodeToDartString(
  CPython cpython,
  Pointer<PyObject> unicodeObjPtr,
) {
  final cStr = cpython.PyUnicode_AsUTF8(unicodeObjPtr);
  if (cStr == nullptr) return null;
  return cStr.cast<Utf8>().toDartString();
}

String? _pyObjectToDartString(CPython cpython, Pointer<PyObject> objPtr) {
  final strObj = cpython.PyObject_Str(objPtr);
  if (strObj == nullptr) return null;
  try {
    return _pyUnicodeToDartString(cpython, strObj);
  } finally {
    cpython.Py_DecRef(strObj);
  }
}
