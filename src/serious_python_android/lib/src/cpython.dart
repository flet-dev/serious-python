import 'dart:async';
import 'dart:ffi';
import 'dart:io';
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

  String outFilename = "stdout.txt";

  // redirect output
  String wrapScript = """
import traceback, sys
_out_f = open("$outFilename", "w")
sys.stdout = sys.stderr = _out_f

try:
    import $programModuleName
except Exception as e:
    traceback.print_exception(e)
finally:
    _out_f.close()
""";

  // run before script
  final wrapScriptPtr = wrapScript.toNativeUtf8();
  int bsr = cpython.PyRun_SimpleString(wrapScriptPtr.cast<Char>());
  debugPrint("PyRun_SimpleString for wrapScript result: $bsr");
  malloc.free(wrapScriptPtr);

  var result = "";

  cpython.Py_Finalize();
  debugPrint("after Py_Finalize()");

  var outFile = File(outFilename);
  if (await outFile.exists()) {
    result = await outFile.readAsString();
  }

  sendPort.send(result);

  return result;
}
