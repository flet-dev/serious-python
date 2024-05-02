import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'gen.dart';

export 'gen.dart';

CPython? _cpython;

CPython getCPython(String dynamicLibPath) {
  return _cpython ??= _cpython = CPython(DynamicLibrary.open(dynamicLibPath));
}

Future<String> runPythonProgramFFI(bool sync, String dynamicLibPath,
    String pythonProgramPath, String script) async {
  final receivePort = ReceivePort();
  if (sync) {
    // sync run
    return await runPythonProgramInIsolate(
        [receivePort.sendPort, dynamicLibPath, pythonProgramPath, script]);
  } else {
    var completer = Completer<String>();
    // async run
    final isolate = await Isolate.spawn(runPythonProgramInIsolate,
        [receivePort.sendPort, dynamicLibPath, pythonProgramPath, script]);
    receivePort.listen((message) {
      receivePort.close();
      isolate.kill();
      completer.complete(message);
    });
    return completer.future;
  }
}

Future<String> runPythonProgramInIsolate(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final dynamicLibPath = arguments[1] as String;
  final pythonProgramPath = arguments[2] as String;
  final script = arguments[3] as String;

  var programDirPath = p.dirname(pythonProgramPath);
  var programModuleName = p.basenameWithoutExtension(pythonProgramPath);

  debugPrint("dynamicLibPath: $dynamicLibPath");
  debugPrint("programDirPath: $programDirPath");
  debugPrint("programModuleName: $programModuleName");

  final cpython = getCPython(dynamicLibPath);
  cpython.Py_Initialize();
  debugPrint("after Py_Initialize()");

  var result = "";

  if (script != "") {
    // run script
    final scriptPtr = script.toNativeUtf8();
    int sr = cpython.PyRun_SimpleString(scriptPtr.cast<Char>());
    debugPrint("PyRun_SimpleString for script result: $sr");
    malloc.free(scriptPtr);
    if (sr != 0) {
      result = "Error running Python script";
    }
  } else {
    // run program
    final moduleNamePtr = programModuleName.toNativeUtf8();
    var modulePtr = cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());
    if (modulePtr == nullptr) {
      final pType =
          calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
      final pValue =
          calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
      final pTrace =
          calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());

      // https://stackoverflow.com/questions/1796510/accessing-a-python-traceback-from-the-c-api
      //cpython.PyErr_Fetch(pType, pValue, pTrace);
      var exPtr = cpython.PyErr_GetRaisedException();

      final funcName = "__traceback__".toNativeUtf8();
      final pFunc = cpython.PyObject_GetAttrString(exPtr, funcName.cast());
      cpython.Py_DecRef(funcName.cast());

      var pTraceback = cpython.PyObject_Str(pFunc);
      var trace =
          cpython.PyUnicode_AsUTF8(pTraceback).cast<Utf8>().toDartString();

      // var pTypeStr = cpython.PyObject_Str(pType.value);
      // var type = cpython.PyUnicode_AsUTF8(pTypeStr).cast<Utf8>().toDartString();

      // var pValueStr = cpython.PyObject_Str(pValue.value);
      // var value =
      //     cpython.PyUnicode_AsUTF8(pValueStr).cast<Utf8>().toDartString();

      // var pTraceStr = cpython.PyObject_Str(pTrace.value);
      // var trace =
      //     cpython.PyUnicode_AsUTF8(pTraceStr).cast<Utf8>().toDartString();

      var pExStr = cpython.PyObject_Str(exPtr);
      var ex = cpython.PyUnicode_AsUTF8(pExStr).cast<Utf8>().toDartString();

      final tracebackModuleNamePtr = "traceback".toNativeUtf8();
      var tracebackModulePtr =
          cpython.PyImport_ImportModule(tracebackModuleNamePtr.cast<Char>());
      cpython.Py_DecRef(tracebackModuleNamePtr.cast());

      if (tracebackModulePtr != nullptr) {
        debugPrint("Traceback module loaded");

        final formatFuncName = "format_exception".toNativeUtf8();
        final pFormatFunc = cpython.PyObject_GetAttrString(
            tracebackModulePtr, formatFuncName.cast());

        cpython.Py_DecRef(funcName.cast());
        if (pFormatFunc != nullptr &&
            cpython.PyCallable_Check(pFormatFunc) != 0) {
          final pArgs = cpython.PyTuple_New(1);
          cpython.PyTuple_SetItem(pArgs, 0, exPtr);
          // cpython.PyTuple_SetItem(pArgs, 1, pValue.value);
          // cpython.PyTuple_SetItem(pArgs, 2, pTrace.value);

          debugPrint("AFTER TUPLE");

          var pythVal = cpython.PyObject_CallObject(pFormatFunc, pArgs);

          debugPrint("AFTER CALL OBJECT");

          var pStack = cpython.PyObject_Str(pythVal);
          var stack =
              cpython.PyUnicode_AsUTF8(pStack).cast<Utf8>().toDartString();
          debugPrint("Stack: $stack");
        }
      }

      // debugPrint("Type: $type");
      // debugPrint("Value: $value");
      debugPrint("Trace: $trace");
      debugPrint("Ex: $ex");

      result = "Error running Python program";
    }
    malloc.free(moduleNamePtr);
  }

  cpython.Py_Finalize();
  debugPrint("after Py_Finalize()");

  sendPort.send(result);

  return result;
}
