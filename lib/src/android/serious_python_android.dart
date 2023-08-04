import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../serious_python_platform_interface.dart';
import '../utils.dart';
import 'cpython.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class SeriousPythonAndroid extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('android_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<String?> run(String appPath,
      {List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    // set environment variables
    if (environmentVariables != null) {
      for (var v in environmentVariables.entries) {
        await methodChannel.invokeMethod<String>(
            'setEnvironmentVariable', {'name': v.key, 'value': v.value});
      }
    }

    // unpack python bundle
    final nativeLibraryDir =
        await methodChannel.invokeMethod<String>('getNativeLibraryDir');
    debugPrint("getNativeLibraryDir: $nativeLibraryDir");

    var bundlePath = "$nativeLibraryDir/libpythonbundle.so";

    if (!await File(bundlePath).exists()) {
      throw Exception("Python bundle not found: $bundlePath");
    }

    var pythonLibPath =
        await extractFileZip(bundlePath, targetPath: "python_bundle");

    debugPrint("pythonLibPath: $pythonLibPath");

    final receivePort = ReceivePort();
    if ((sync ?? false) == false) {
      // async run
      final isolate = await Isolate.spawn(runPythonProgram,
          [receivePort.sendPort, pythonLibPath, appPath, modulePaths ?? []]);
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
    } else {
      // sync run
      runPythonProgram(
          [receivePort.sendPort, pythonLibPath, appPath, modulePaths ?? []]);
    }

    return null;
  }
}

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

void runPythonProgram(List<Object> arguments) async {
  final sendPort = arguments[0] as SendPort;
  final pythonLibPath = arguments[1] as String;
  final pythonProgramPath = arguments[2] as String;
  final modulePaths = arguments[3] as List<String>;

  var programDirPath = p.dirname(pythonProgramPath);
  var programModuleName = p.basenameWithoutExtension(pythonProgramPath);

  var programDirPathFiles = await getDirFiles(programDirPath);
  var pythonLibPathFiles = await getDirFiles(pythonLibPath);

  debugPrint("programDirPath: $programDirPath");
  debugPrint("programModuleName: $programModuleName");
  debugPrint("pythonLibPath: $pythonLibPath");
  debugPrint("programDirPathFiles: $programDirPathFiles");
  debugPrint("pythonLibPathFiles: $pythonLibPathFiles");

  var loadDynamicLibraries = [
    "libffi.so",
    "libcrypto1.1.so",
    "libsqlite3.so",
    "libssl1.1.so",
    "libpython3.10.so"
  ];

  var moduleSearchPaths = [
    programDirPath,
    "$programDirPath/__pypackages__",
    ...modulePaths,
    "$pythonLibPath/modules",
    "$pythonLibPath/site-packages",
    "$pythonLibPath/stdlib.zip"
  ];

  // load dynamic libraries
  for (var loadDynamicLibrary in loadDynamicLibraries) {
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
  var modulePtr = cpython.PyImport_ImportModule(moduleNamePtr.cast<Char>());
  if (modulePtr == nullptr) {
    final pType =
        calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    final pValue =
        calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    final pTrace =
        calloc.allocate<Pointer<PyObject>>(sizeOf<Pointer<PyObject>>());
    cpython.PyErr_Fetch(pType, pValue, pTrace);
    cpython.PyErr_NormalizeException(pType, pValue, pTrace);
    cpython.PyErr_Display(pType.value, pValue.value, pTrace.value);
  }
  // final pythonCodePtr = pythonCode.toNativeUtf8();
  // int r = dartpyc.PyRun_SimpleString(pythonCodePtr.cast<Char>());
  // debugPrint("PyRun_SimpleString result: $r");
  // malloc.free(pythonCodePtr);

  cpython.Py_Finalize();
  debugPrint("after Py_Finalize");
  sendPort.send("Python program exited");
}

Future<String> getDirFiles(String path, {bool recursive = false}) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    return "<not found>";
  }
  return (await dir.list(recursive: recursive).toList())
      .map((file) => file.path)
      .join('\n');
}
