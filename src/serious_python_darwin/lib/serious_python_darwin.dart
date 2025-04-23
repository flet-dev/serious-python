import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class SeriousPythonDarwin extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python');

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonDarwin();
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    Future setenv(String key, String value) async {
      await methodChannel.invokeMethod<String>(
          'setEnvironmentVariable', {'name': key, 'value': value});
    }

    // get python bundle path
    final pythonBundlePath =
        await methodChannel.invokeMethod<String>('getPythonBundlePath');
    debugPrint("pythonBundlePath: $pythonBundlePath");

    var programDirPath = p.dirname(appPath);

    var moduleSearchPaths = [
      programDirPath,
      ...?modulePaths,
      "$programDirPath/__pypackages__",
      "$pythonBundlePath/site-packages",
      "$pythonBundlePath/stdlib",
      "$pythonBundlePath/stdlib/lib-dynload"
    ];

    setenv("PYTHONINSPECT", "1");
    setenv("PYTHONDONTWRITEBYTECODE", "1");
    setenv("PYTHONNOUSERSITE", "1");
    setenv("PYTHONUNBUFFERED", "1");
    setenv("LC_CTYPE", "UTF-8");
    setenv("PYTHONHOME", programDirPath);
    setenv("PYTHONPATH", moduleSearchPaths.join(":"));

    // set environment variables
    if (environmentVariables != null) {
      for (var v in environmentVariables.entries) {
        setenv(v.key, v.value);
      }
    }

    final execPath = Platform.resolvedExecutable;
    final appContents = Directory(execPath).parent.parent;

    var dartBridgeLib = DynamicLibrary.open(
        '$programDirPath/__pypackages__/dart_bridge.abi3.so');

    /// Dart_InitializeApiDL(void* init_data)
    final int Function(Pointer<Void>) dartInitializeApiDL = dartBridgeLib
        .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
            'DartBridge_InitDartApiDL')
        .asFunction();

    /// void set_dart_send_port(int64_t port_id)
    final void Function(int) setDartSendPort = dartBridgeLib
        .lookup<NativeFunction<Void Function(Int64)>>('DartBridge_SetSendPort')
        .asFunction();

    final void Function(Pointer<Char>, int) enqueueMessageFromDart =
        dartBridgeLib
            .lookup<NativeFunction<Void Function(Pointer<Char>, IntPtr)>>(
                'DartBridge_EnqueueMessage')
            .asFunction();

    // 1. Initialize Dart Native API
    final initResult = dartInitializeApiDL(NativeApi.initializeApiDLData);
    if (initResult != 0) {
      throw Exception('Failed to initialize Dart API: error code $initResult');
    }

    // 2. Set up ReceivePort
    final receivePort = ReceivePort();
    final nativePort = receivePort.sendPort.nativePort;

    print('✅ Native port: $nativePort');
    setDartSendPort(nativePort);

    receivePort.listen((message) {
      if (message is Uint8List) {
        print('📥 Received message: ${String.fromCharCodes(message)}');
      } else {
        print('⚠️ Unexpected message type: $message');
      }
    });

    runPythonProgramFFI(
        sync ?? false,
        "${appContents.path}/Frameworks/Python.framework/Python",
        appPath,
        script ?? "");

    await Future.delayed(const Duration(seconds: 1));

    for (int i = 0; i < 10; i++) {
      if (i == 0) print("🧪 Sending first message from Dart...");
      String message = "aaa bbb ccc $i";
      final Pointer<Char> ptr = message.toNativeUtf8().cast<Char>();
      enqueueMessageFromDart(ptr, message.length);
      calloc.free(ptr);

      print("After calling enqueueMessageFromDart: $i");
      await Future.delayed(const Duration(milliseconds: 1));
    }

    var appLifecycleListener = AppLifecycleListener(onExitRequested: () async {
      print('🛑 App exit requested!');

      String message = "\$shutdown";
      final Pointer<Char> ptr = message.toNativeUtf8().cast<Char>();
      enqueueMessageFromDart(ptr, message.length);
      calloc.free(ptr);

      return AppExitResponse.exit;
    });

    // ProcessSignal.sigint.watch().listen((signal) {
    //   print('🚨 SIGINT received — triggering shutdown...');
    //   String message = "\$shutdown";
    //   final Pointer<Char> ptr = message.toNativeUtf8().cast<Char>();
    //   enqueueMessageFromDart(ptr, message.length);
    //   calloc.free(ptr);
    // });

    return null;
  }
}
