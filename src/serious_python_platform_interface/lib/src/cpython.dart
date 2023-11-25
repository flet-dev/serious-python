import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'gen.dart';
import 'utils.dart';

export 'gen.dart';

CPython? _cpython;

CPython getCPython(String dynamicLibPath) {
  return _cpython ??= _cpython = CPython(DynamicLibrary.open(dynamicLibPath));
}

Future<Isolate?> runPythonProgramFFI(
    bool sync, String dynamicLibPath, String pythonProgramPath) async {
  final receivePort = ReceivePort();
  if (sync) {
    // sync run
    runPythonProgramInIsolate([
      receivePort.sendPort,
      dynamicLibPath,
      pythonProgramPath,
    ]);
    return null;
  } else {
    // async run
    final isolate = await Isolate.spawn(runPythonProgramInIsolate, [
      receivePort.sendPort,
      dynamicLibPath,
      pythonProgramPath,
    ]);
    receivePort.listen((message) {
      debugPrint(message);
      receivePort.close();
      isolate.kill();

      var out = File("out.txt");
      if (out.existsSync()) {
        var r = out.readAsStringSync();
        debugPrint("Result from out.txt: $r");
      }
    });
    return isolate;
  }
}

void runPythonProgramInIsolate(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final dynamicLibPath = arguments[1] as String;
  final pythonProgramPath = arguments[2] as String;

  var programDirPath = p.dirname(pythonProgramPath);
  var programModuleName = p.basenameWithoutExtension(pythonProgramPath);

  var programDirPathFiles = await getDirFiles(programDirPath);

  debugPrint("dynamicLibPath: $dynamicLibPath");
  debugPrint("programDirPath: $programDirPath");
  debugPrint("programModuleName: $programModuleName");
  debugPrint("programDirPathFiles: $programDirPathFiles");

  final cpython = getCPython(dynamicLibPath);
  cpython.Py_Initialize();

  // run user program
  final moduleNamePtr = programModuleName.toNativeUtf8();
  var modulePtr = cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());

  var result = "Python program exited";
  if (modulePtr == nullptr) {
    // final pType =
    //     calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    // final pValue =
    //     calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    // final pTrace =
    //     calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    // cpython.PyErr_Fetch(pType, pValue, pTrace);
    // cpython.PyErr_NormalizeException(pType, pValue, pTrace);
    // cpython.PyErr_Display(pType.value, pValue.value, pTrace.value);
    result = "Error running Python program";
  }

  // final pythonCodePtr = pythonCode.toNativeUtf8();
  // int r = dartpyc.PyRun_SimpleString(pythonCodePtr.cast<Char>());
  // debugPrint("PyRun_SimpleString result: $r");
  // malloc.free(pythonCodePtr);

  cpython.Py_Finalize();
  debugPrint("after Py_Finalize");
  sendPort.send(result);
}
