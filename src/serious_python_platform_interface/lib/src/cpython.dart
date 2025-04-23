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
    runPythonProgramInIsolate(
        [receivePort.sendPort, dynamicLibPath, pythonProgramPath, script]);
  } else {
    var completer = Completer<String>();
    // async run
    final isolate = await Isolate.spawn(runPythonProgramInIsolate,
        [receivePort.sendPort, dynamicLibPath, pythonProgramPath, script]);

    receivePort.listen((message) {
      //receivePort.close();
      //print("Isolate killed!");
      //isolate.kill();
      //completer.complete(message);
    });
    //print("after isolate call");
    // return completer.future;
  }

  return "";
}

dynamic _modulePtr;

Future<void> runPythonProgramInIsolate(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final dynamicLibPath = arguments[1] as String;
  final pythonProgramPath = arguments[2] as String;
  final script = arguments[3] as String;

  //final receivePort = ReceivePort(); // ✅ to keep isolate alive
  //sendPort.send(receivePort.sendPort);

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
      result = getPythonError(cpython);
    }
  } else {
    // run program
    final moduleNamePtr = programModuleName.toNativeUtf8();
    _modulePtr = cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());
    if (_modulePtr == nullptr) {
      result = getPythonError(cpython);
      print("result: $result");
    }
    malloc.free(moduleNamePtr);

    // final funcName = 'enqueue_message'.toNativeUtf8();
    // final enqueueFunc =
    //     cpython.PyObject_GetAttrString(modulePtr, funcName.cast());
    // calloc.free(funcName);

    // // send message into python script

    // final bytes = "some message!".codeUnits;

    // final pointer = calloc<Int8>(bytes.length);
    // for (int i = 0; i < bytes.length; i++) {
    //   pointer[i] = bytes[i];
    // }

    // final pyBytes =
    //     cpython.PyBytes_FromStringAndSize(pointer.cast(), bytes.length);
    // final args = cpython.PyTuple_New(1);
    // cpython.PyTuple_SetItem(args, 0, pyBytes);
    // final r = cpython.PyObject_CallObject(enqueueFunc, args);

    // if (r == nullptr) {
    //   print('[Dart] Python error occurred');
    //   cpython.PyErr_Print();
    // } else {
    //   print('[Dart] Sent message to Python');
    // }
  }

  // cpython.Py_Finalize();
  // debugPrint("after Py_Finalize()");

  // await Future.delayed(const Duration(seconds: 5));

  //sendPort.send(result);

  // 🧠 Now just wait forever to keep isolate (and Python loop) alive
  print("Before receivePort.first");
  //await receivePort.first; // or .listen(...) if needed
  print("After receivePort.first");
  //sendPort.send(true);
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
    //debugPrint("Traceback module loaded");

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
