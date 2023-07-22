import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils.dart';
import 'cpython.dart';

/*

Getting struct member offsets.

Create `myprogram.c`:

----------------------------------------
#include <Python.h>
#include <stddef.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
    printf("Offset of PyConfig.home: %zu\n", offsetof(PyConfig, home));
    printf("Offset of PyConfig.module_search_paths: %zu\n", offsetof(PyConfig, module_search_paths));
    printf("Offset of PyConfig.pythonpath_env: %zu\n", offsetof(PyConfig, pythonpath_env));

    Py_Initialize();
    PyRun_SimpleString("from time import time,ctime\n"
                       "print('Today is', ctime(time()))\n");
    Py_Finalize();
    return 0;
}
----------------------------------------

Build:

gcc -o myprogram myprogram.c -I$HOME/.pyenv/versions/3.10.10/include/python3.10 -L$HOME/.pyenv/versions/3.10.10/lib -lpython3.10

Run:

./myprogram

*/

const pyConfigPythonpathEnvOffset = 248;
const pyConfigHomeOffset = 256;
const pyConfigModuleSearchPathsOffset = 280;

void runPyProgram(List<Object> arguments) async {
  SendPort sendPort = arguments[0] as SendPort;
  String pythonLibPath = arguments[1] as String;
  var pythonCode = """
import threading
import time
import sys
import os

#os.environ["PYTHONINSPECT"] = "1"

def th1():
    for i in range(10):
        print("Thread 1:", i)
        with open("t1.txt", "w") as f:
            f.write(f"b-{i}")
        time.sleep(1)


def th2():
    for i in range(10):
        print("Thread 2:", i)
        with open("t2.txt", "w") as f:
            f.write(f"{i}")
        time.sleep(0.5)

#sys.exit(1)

t1 = threading.Thread(target=th1, daemon=True)
t1.start()

t2 = threading.Thread(target=th2, daemon=True)
t2.start()

print("Program started")
time.sleep(5)

with open("out.txt", "w") as f:
    f.write(str(sys.path))
    #f.write(str(sys.home))
    for name, value in os.environ.items():
        f.write("{0}: {1}\\n".format(name, value))

""";

  var pythonHomePtr = cpython.Py_DecodeLocale(
      pythonLibPath.toNativeUtf8().cast<Char>(), nullptr);

  var pythonPathEnvPtr = cpython.Py_DecodeLocale(
      "$pythonLibPath/modules:$pythonLibPath/site-packages:$pythonLibPath/stdlib.zip"
          .toNativeUtf8()
          .cast<Char>(),
      nullptr);

  DynamicLibrary.open("libffi.so");

  cpython.Py_SetPythonHome(pythonHomePtr);
  cpython.Py_SetPath(pythonPathEnvPtr);

  cpython.Py_Initialize();

  malloc.free(pythonHomePtr);
  malloc.free(pythonPathEnvPtr);

  Directory.current = pythonLibPath;

  // run user program
  final pythonCodePtr = pythonCode.toNativeUtf8();
  int r = cpython.PyRun_SimpleString(pythonCodePtr.cast<Char>());
  debugPrint("PyRun_SimpleString: $r");
  malloc.free(pythonCodePtr);

  cpython.Py_Finalize();
  debugPrint("after run");
  sendPort.send("Python program exited");
}

void runPyProgramExp(List<Object> arguments) async {
  SendPort sendPort = arguments[0] as SendPort;
  String pythonLibPath = arguments[1] as String;
  String pythonProgramPath = arguments[2] as String;

  var programDirPath = p.dirname(pythonProgramPath);
  var programModuleName = p.basenameWithoutExtension(pythonProgramPath);

  var loadLynamicLibraries = [
    "libffi.so",
    "libcrypto1.1.so",
    "libsqlite3.so",
    "libssl1.1.so",
    "libpython3.10.so"
  ];

  var moduleSearchPaths = [
    programDirPath,
    "$programDirPath/__pypackages__",
    "$pythonLibPath/modules",
    "$pythonLibPath/site-packages",
    "$pythonLibPath/stdlib.zip"
  ];

  var currentDir = pythonLibPath;

  // set current dir
  Directory.current = currentDir;

  // load dynamic libraries
  for (var loadDynamicLibrary in loadLynamicLibraries) {
    DynamicLibrary.open(loadDynamicLibrary);
  }

  // pre config
  final pyPreConfig = calloc.allocate<PyPreConfig>(sizeOf<PyPreConfig>());
  cpython.PyPreConfig_InitIsolatedConfig(pyPreConfig);
  pyPreConfig.ref.utf8_mode = 1;
  cpython.Py_PreInitialize(pyPreConfig);

  // config
  final pyConfig = calloc.allocate<PyConfig>(sizeOf<PyConfig>());
  cpython.PyConfig_InitIsolatedConfig(pyConfig);

  // config.home
  Pointer<Pointer<WChar>> configHomePtr =
      Pointer.fromAddress(pyConfig.address + pyConfigHomeOffset).cast();

  var homeValuePtr = cpython.Py_DecodeLocale(
      pythonLibPath.toNativeUtf8().cast<Char>(), nullptr);

  cpython.PyConfig_SetString(pyConfig, configHomePtr, homeValuePtr);
  malloc.free(homeValuePtr);

  // config.pythonpath_env
  Pointer<Pointer<WChar>> configPythonPathEnvPtr =
      Pointer.fromAddress(pyConfig.address + pyConfigPythonpathEnvOffset)
          .cast();

  var pythonPathEnvValuePtr = cpython.Py_DecodeLocale(
      "$pythonLibPath/modules:$pythonLibPath/site-packages:$pythonLibPath/stdlib.zip"
          .toNativeUtf8()
          .cast<Char>(),
      nullptr);

  cpython.PyConfig_SetString(
      pyConfig, configPythonPathEnvPtr, pythonPathEnvValuePtr);
  malloc.free(pythonPathEnvValuePtr);

  // rest of the config
  pyConfig.ref.inspect = 1;
  pyConfig.ref.module_search_paths_set = 1;

  cpython.PyConfig_Read(pyConfig);

  // config.module_search_paths
  Pointer<PyWideStringList> moduleSearchPathsPtr =
      Pointer.fromAddress(pyConfig.address + pyConfigModuleSearchPathsOffset)
          .cast();

  for (var moduleSerachPath in moduleSearchPaths) {
    var p = cpython.Py_DecodeLocale(
        moduleSerachPath.toNativeUtf8().cast<Char>(), nullptr);

    cpython.PyWideStringList_Append(moduleSearchPathsPtr, p);
    malloc.free(p);
  }

  debugPrint("before Py_InitializeFromConfig");
  cpython.Py_InitializeFromConfig(pyConfig);
  debugPrint("after Py_InitializeFromConfig");

  // run user program
  final moduleNamePtr = programModuleName.toNativeUtf8();
  cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());
  // final pythonCodePtr = pythonCode.toNativeUtf8();
  // int r = dartpyc.PyRun_SimpleString(pythonCodePtr.cast<Char>());
  // debugPrint("PyRun_SimpleString result: $r");
  // malloc.free(pythonCodePtr);

  cpython.Py_Finalize();
  debugPrint("after Py_Finalize");
  sendPort.send("Python program exited");
}

Future runPy() async {
  var pythonLibPath = await extractAssetZip(
      "packages/serious_python_android/assets/python-lib-arm64-v8a.zip");
  var programDirPath = await extractAssetZip("assets/main.py.zip");
  var programPath = "$programDirPath/main.py";

  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
      runPyProgramExp, [receivePort.sendPort, pythonLibPath, programPath]);

  receivePort.listen((message) {
    debugPrint(message);
    receivePort.close();
    isolate.kill();

    var r2 = File("$pythonLibPath/out.txt").readAsStringSync();
    debugPrint("Result out.txt: $r2");
  });
}
