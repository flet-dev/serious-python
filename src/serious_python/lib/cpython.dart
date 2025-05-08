import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// C struct equivalent:
// typedef struct {
//   const char* appPath;
//   const char* script;
//   const char** modulePaths;
//   int modulePathCount;
//   const char** environmentKeys;
//   const char** environmentValues;
//   int environmentCount;
//   int sync; // 1 for sync, 0 for async
// } RunPythonArgs;

final class RunPythonArgs extends Struct {
  external Pointer<Utf8> appPath;
  external Pointer<Utf8> script;

  external Pointer<Pointer<Utf8>> modulePaths;
  @Int32()
  external int modulePathCount;

  external Pointer<Pointer<Utf8>> environmentKeys;
  external Pointer<Pointer<Utf8>> environmentValues;
  @Int32()
  external int environmentCount;

  @Int32()
  external int sync;
}

// C function signature:
// int DartBridge_RunPython(RunPythonArgs* args);

typedef DartBridgeRunPythonNative = Int32 Function(Pointer<RunPythonArgs> args);
typedef DartBridgeRunPython = int Function(Pointer<RunPythonArgs> args);

/// Bindings to Python C interface
/// ignore_for_file: unused_field, unused_element
///
class CPython {
  static CPython? _instance;
  final DynamicLibrary _dynamicLibrary;

  late final DartBridgeRunPython _runPython = _dynamicLibrary
      .lookup<NativeFunction<DartBridgeRunPythonNative>>('DartBridge_RunPython')
      .asFunction<DartBridgeRunPython>();

  /// Dart_InitializeApiDL(void* init_data)
  late final int Function(Pointer<Void>) _dartInitializeApiDL = _dynamicLibrary
      .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
          'DartBridge_InitDartApiDL')
      .asFunction();

  /// void set_dart_send_port(int64_t port_id)
  late final void Function(int) _setDartSendPort = _dynamicLibrary
      .lookup<NativeFunction<Void Function(Int64)>>('DartBridge_SetSendPort')
      .asFunction();

  late final void Function(Pointer<Char>, int) _enqueueMessageFromDart =
      _dynamicLibrary
          .lookup<NativeFunction<Void Function(Pointer<Char>, IntPtr)>>(
              'DartBridge_EnqueueMessage')
          .asFunction();

  /// Private constructor
  CPython._(this._dynamicLibrary) {
    final initResult = _dartInitializeApiDL(NativeApi.initializeApiDLData);
    if (initResult != 0) {
      throw Exception('Failed to initialize Dart API: error code $initResult');
    }
    debugPrint("CPython library initialized.");
  }

  /// Factory constructor that returns the singleton
  factory CPython(DynamicLibrary dynamicLibrary) {
    return _instance ??= CPython._(dynamicLibrary);
  }

  void setDartSendPort(int nativePort) {
    debugPrint("Set Dart native port: $nativePort");
    _setDartSendPort(nativePort);
  }

  void sendMessageToPython(Uint8List message) {
    final Pointer<Uint8> ptr = calloc<Uint8>(message.length);
    for (int i = 0; i < message.length; i++) {
      ptr[i] = message[i];
    }
    _enqueueMessageFromDart(ptr.cast<Char>(), message.length);
    calloc.free(ptr);
  }

  void runPython(
      {required String appPath,
      required String script,
      required List<String> modules,
      required Map<String, String> envVars,
      required bool sync}) {
    final appPathPtr = appPath.toNativeUtf8();
    final scriptPtr = script.toNativeUtf8();

    final Pointer<Pointer<Utf8>> modulesPtr =
        malloc.allocate(modules.length * sizeOf<Pointer<Utf8>>());
    for (int i = 0; i < modules.length; i++) {
      modulesPtr[i] = modules[i].toNativeUtf8();
    }

    final Pointer<Pointer<Utf8>> keysPtr =
        malloc.allocate(envVars.length * sizeOf<Pointer<Utf8>>());
    final Pointer<Pointer<Utf8>> valuesPtr =
        malloc.allocate(envVars.length * sizeOf<Pointer<Utf8>>());

    final keys = envVars.keys.toList();
    final values = envVars.values.toList();
    for (int i = 0; i < envVars.length; i++) {
      keysPtr[i] = keys[i].toNativeUtf8();
      valuesPtr[i] = values[i].toNativeUtf8();
    }

    // print("envVars: $envVars");
    // print("modules: $modules");

    final argsPtr = malloc<RunPythonArgs>();
    argsPtr.ref
      ..appPath = appPathPtr
      ..script = scriptPtr
      ..modulePaths = modulesPtr
      ..modulePathCount = modules.length
      ..environmentKeys = keysPtr
      ..environmentValues = valuesPtr
      ..environmentCount = envVars.length
      ..sync = sync ? 1 : 0;

    _runPython(argsPtr);

    if (sync) {
      // Optional: free memory later if you won’t reuse it
      malloc.free(appPathPtr);
      malloc.free(scriptPtr);
      for (int i = 0; i < modules.length; i++) {
        malloc.free(modulesPtr[i]);
      }
      malloc.free(modulesPtr);
      for (int i = 0; i < envVars.length; i++) {
        malloc.free(keysPtr[i]);
        malloc.free(valuesPtr[i]);
      }
      malloc.free(keysPtr);
      malloc.free(valuesPtr);
      malloc.free(argsPtr);
    }
  }
}
