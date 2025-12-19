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
var _pythonRunSeq = 0;

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
    root.setLevel(logging.DEBUG)
''';

CPython getCPython(String dynamicLibPath) {
  return _cpython ??= _cpython = CPython(DynamicLibrary.open(dynamicLibPath));
}

Future<String> runPythonProgramFFI(bool sync, String dynamicLibPath,
    String pythonProgramPath, String script) async {
  return _enqueuePythonRun(() async {
    final runId = ++_pythonRunSeq;
    spDebug(
        "Python run#$runId start (sync=$sync, script=${script.isNotEmpty}, program=$pythonProgramPath)");
    if (sync) {
      // Sync run: do not involve ports (avoids GC/close races).
      final result =
          _runPythonProgram(dynamicLibPath, pythonProgramPath, script);
      spDebug("Python run#$runId done (resultLength=${result.length})");
      return result;
    } else {
      // Async run: use Isolate.run() to avoid manual port lifecycle issues.
      try {
        final result = await Isolate.run(
            () => _runPythonProgram(dynamicLibPath, pythonProgramPath, script));
        spDebug("Python run#$runId done (resultLength=${result.length})");
        return result;
      } catch (e, st) {
        final message = "Dart error running Python: $e\n$st";
        spDebug(message);
        spDebug("Python run#$runId failed");
        return message;
      }
    }
  });
}

Future<String> runPythonProgramInIsolate(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final dynamicLibPath = arguments[1] as String;
  final pythonProgramPath = arguments[2] as String;
  final script = arguments[3] as String;

  try {
    final result = _runPythonProgram(dynamicLibPath, pythonProgramPath, script);
    sendPort.send(result);
    return result;
  } catch (e, st) {
    final message = "Dart error running Python: $e\n$st";
    spDebug(message);
    sendPort.send(message);
    return message;
  }
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
    spDebug("Python already initialized, skipping execution.");
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
  // get error object
  var exPtr = cpython.PyErr_GetRaisedException();

  // use 'traceback' module to format exception
  final tracebackModuleNamePtr = "traceback".toNativeUtf8();
  var tracebackModulePtr =
      cpython.PyImport_ImportModule(tracebackModuleNamePtr.cast<Char>());
  cpython.Py_DecRef(tracebackModuleNamePtr.cast());

  if (tracebackModulePtr != nullptr) {
    //spDebug("Traceback module loaded");

    final formatFuncName = "format_exception".toNativeUtf8();
    final pFormatFunc = cpython.PyObject_GetAttrString(
        tracebackModulePtr, formatFuncName.cast());
    cpython.Py_DecRef(tracebackModuleNamePtr.cast());

    if (pFormatFunc != nullptr && cpython.PyCallable_Check(pFormatFunc) != 0) {
      // call `traceback.format_exception()` method
      final pArgs = cpython.PyTuple_New(1);
      cpython.PyTuple_SetItem(pArgs, 0, exPtr);

      // result is a list
      var listPtr = cpython.PyObject_CallObject(pFormatFunc, pArgs);

      // get and combine list items
      var exLines = [];
      var listSize = cpython.PyList_Size(listPtr);
      for (var i = 0; i < listSize; i++) {
        var itemObj = cpython.PyList_GetItem(listPtr, i);
        var itemObjStr = cpython.PyObject_Str(itemObj);
        var s =
            cpython.PyUnicode_AsUTF8(itemObjStr).cast<Utf8>().toDartString();
        exLines.add(s);
      }
      return exLines.join("");
    } else {
      return "traceback.format_exception() method not found.";
    }
  } else {
    return "Error loading traceback module.";
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
