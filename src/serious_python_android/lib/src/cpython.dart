import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'gen.dart';
import 'log.dart';

export 'gen.dart';

CPython? _cpython;
String? _logcatForwardingError;
Future<void> _pythonRunQueue = Future<void>.value();

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

const _logcatInitScript = r'''
import logging,sys

# Make this init idempotent across Dart isolate restarts.
if not getattr(sys, "__serious_python_logcat_configured__", False):
    sys.__serious_python_logcat_configured__ = True

    from ctypes import cdll
    liblog = cdll.LoadLibrary("liblog.so")
    ANDROID_LOG_INFO = 4

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

CPython getCPython(String dynamicLibPath) {
  return _cpython ??= _cpython = CPython(DynamicLibrary.open(dynamicLibPath));
}

Future<String> runPythonProgramFFI(bool sync, String dynamicLibPath,
    String pythonProgramPath, String script) async {
  return _enqueuePythonRun(() async {
    spDebug(
        "Python run start (sync=$sync, script=${script.isNotEmpty}, program=$pythonProgramPath)");
    if (sync) {
      // Sync run: do not involve ports (avoids GC/close races).
      final result =
          _runPythonProgram(dynamicLibPath, pythonProgramPath, script);
      spDebug("Python run done (resultLength=${result.length})");
      return result;
    } else {
      // Async run: use Isolate.run() to avoid manual port lifecycle issues.
      try {
        final result = await Isolate.run(
            () => _runPythonProgram(dynamicLibPath, pythonProgramPath, script));
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

String _runPythonProgram(
    String dynamicLibPath, String pythonProgramPath, String script) {
  var programDirPath = p.dirname(pythonProgramPath);
  var programModuleName = p.basenameWithoutExtension(pythonProgramPath);

  spDebug("dynamicLibPath: $dynamicLibPath");
  spDebug("programDirPath: $programDirPath");
  spDebug("programModuleName: $programModuleName");

  final cpython = getCPython(dynamicLibPath);
  spDebug("CPython loaded");
  if (cpython.Py_IsInitialized() != 0) {
    spDebug(
        "Python already initialized and another program is running, skipping execution.");
    return "";
  }

  cpython.Py_Initialize();
  spDebug("after Py_Initialize()");

  var result = "";

  final logcatSetupError = _setupLogcatForwarding(cpython);
  if (logcatSetupError != null) {
    cpython.Py_Finalize();
    return logcatSetupError;
  }

  if (script != "") {
    // run script
    final scriptPtr = script.toNativeUtf8();
    int sr = cpython.PyRun_SimpleString(scriptPtr.cast<Char>());
    spDebug("PyRun_SimpleString for script result: $sr");
    malloc.free(scriptPtr);
    if (sr != 0) {
      result = getPythonError(cpython);
    }
  } else {
    // run program
    final moduleNamePtr = programModuleName.toNativeUtf8();
    var modulePtr = cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());
    if (modulePtr == nullptr) {
      result = getPythonError(cpython);
    }
    malloc.free(moduleNamePtr);
  }

  cpython.Py_Finalize();
  spDebug("after Py_Finalize()");

  return result;
}

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
    // Defensive: formatting can set a new Python error.
    cpython.PyErr_Clear();
  }
}

String? _formatPythonException(
    CPython cpython, Pointer<PyObject> exceptionPtr) {
  // Uses `traceback.format_exception(exc)` (Python 3.10+ signature).
  final tracebackModuleNamePtr = "traceback".toNativeUtf8();
  final tracebackModulePtr =
      cpython.PyImport_ImportModule(tracebackModuleNamePtr.cast<Char>());
  malloc.free(tracebackModuleNamePtr);
  if (tracebackModulePtr == nullptr) return null;

  try {
    final formatFuncNamePtr = "format_exception".toNativeUtf8();
    final formatFuncPtr = cpython.PyObject_GetAttrString(
        tracebackModulePtr, formatFuncNamePtr.cast());
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
          final itemObj = cpython.PyList_GetItem(listPtr, i); // borrowed ref
          if (itemObj == nullptr) continue;

          final line = _pyUnicodeToDartString(cpython, itemObj) ??
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
    CPython cpython, Pointer<PyObject> unicodeObjPtr) {
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

String? _setupLogcatForwarding(CPython cpython) {
  if (_logcatForwardingError != null) {
    return _logcatForwardingError;
  }

  final setupPtr = _logcatInitScript.toNativeUtf8();
  final result = cpython.PyRun_SimpleString(setupPtr.cast<Char>());
  malloc.free(setupPtr);

  if (result != 0) {
    _logcatForwardingError = getPythonError(cpython);
    return _logcatForwardingError;
  }

  return null;
}
