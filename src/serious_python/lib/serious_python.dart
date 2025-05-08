import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python/cpython.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

export 'package:serious_python_platform_interface/src/utils.dart';

/// Provides cross-platform functionality for running Python programs.
class SeriousPython {
  static CPython? _cpython;

  SeriousPython._();

  /// Returns the current name and version of the operating system.
  // static Future<String?> getPlatformVersion() {
  //   return SeriousPythonPlatform.instance.getPlatformVersion();
  // }

  /// Runs Python program from an asset.
  ///
  /// [assetPath] is the path to an asset which is a zip archive
  /// with a Python program. When the app starts the archive is unpacked
  /// to a temporary directory and Serious Python plugin will try to run
  /// `main.py` in the root of the archive. Current directory is changed to
  /// a temporary directory.
  ///
  /// If a Python app has a different entry point
  /// it could be specified with [appFileName] parameter.
  ///
  /// Environment variables that must be available to a Python program could
  /// be passed in [environmentVariables].
  ///
  /// By default, Serious Python expects Python dependencies installed into
  /// `__pypackages__` directory in the root of app directory. Additional paths
  /// to look for 3rd-party packages can be specified with [modulePaths] parameter.
  ///
  /// Set [sync] to `true` to sychronously run Python program; otherwise the
  /// program starts in a new thread.
  static Future run(String assetPath,
      {String? appFileName,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync,
      SendPort? sendPort}) async {
    // unpack app from asset
    String appPath = "";
    if (path.extension(assetPath) == ".zip") {
      appPath = await extractAssetZip(assetPath);
      if (appFileName != null) {
        appPath = path.join(appPath, appFileName);
      } else if (await File(path.join(appPath, "main.pyc")).exists()) {
        appPath = path.join(appPath, "main.pyc");
      } else if (await File(path.join(appPath, "main.py")).exists()) {
        appPath = path.join(appPath, "main.py");
      } else {
        throw Exception(
            "App archive must contain either `main.py` or `main.pyc`; otherwise `appFileName` must be specified.");
      }
    } else {
      appPath = await extractAsset(assetPath);
    }

    // set current directory to app path
    Directory.current = path.dirname(appPath);

    // run python program
    return runProgram(appPath,
        modulePaths: modulePaths,
        environmentVariables: environmentVariables,
        script: Platform.isWindows ? "" : null,
        sync: sync,
        sendPort: sendPort);
  }

  /// Runs Python program from a path.
  ///
  /// This is low-level method.
  /// Make sure `Directory.current` is set before calling this method.
  ///
  /// [appPath] is the full path to a .py or .pyc file to run.
  ///
  /// Environment variables that must be available to a Python program could
  /// be passed in [environmentVariables].
  ///
  /// By default, Serious Python expects Python dependencies installed into
  /// `__pypackages__` directory in the root of app directory. Additional paths
  /// to look for 3rd-party packages can be specified with [modulePaths] parameter.
  ///
  /// Set [sync] to `true` to sychronously run Python program; otherwise the
  /// program starts in a new thread.
  static Future runProgram(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync,
      SendPort? sendPort}) async {
    // run before run python program
    await SeriousPythonPlatform.instance.run(appPath,
        script: script,
        modulePaths: modulePaths,
        environmentVariables: environmentVariables,
        sync: sync);

    var dartBridgeLibPath =
        await SeriousPythonPlatform.instance.getDartBridgePath();
    debugPrint("dartBridgeLibPath: $dartBridgeLibPath");

    var pythonModulePaths =
        await SeriousPythonPlatform.instance.getPythonModulePaths();
    debugPrint("pythonModulePaths: $pythonModulePaths");

    // run python program with FFI
    _cpython = CPython(DynamicLibrary.open(dartBridgeLibPath!));

    var programDirPath = path.dirname(appPath);

    // all environment variables
    Map<String, String> envVars = Map.from(environmentVariables ?? {});
    envVars["PYTHONINSPECT"] = "1";
    envVars["PYTHONDONTWRITEBYTECODE"] = "1";
    envVars["PYTHONNOUSERSITE"] = "1";
    envVars["PYTHONUNBUFFERED"] = "1";
    envVars["LC_CTYPE"] = "UTF-8";
    envVars["PYTHONHOME"] = programDirPath;

    // all module paths
    List<String> allModulePaths = [...?pythonModulePaths, ...?modulePaths];

    if (sendPort != null) {
      _cpython!.setDartSendPort(sendPort.nativePort);
    }

    // run Python program or script
    _cpython!.runPython(
        appPath: appPath,
        script: script ?? "",
        modules: allModulePaths,
        envVars: envVars,
        sync: sync ?? false);

    await Future.delayed(const Duration(seconds: 1));

    for (int i = 0; i < 10; i++) {
      if (i == 0) print("🧪 Sending first message from Dart...");
      String message = "aaa bbb ccc $i";
      Uint8List bytes = Uint8List.fromList(utf8.encode(message));

      _cpython!.sendMessageToPython(bytes);

      print("After calling enqueueMessageFromDart: $i");
      await Future.delayed(const Duration(milliseconds: 1));
    }

    // ProcessSignal.sigint.watch().listen((signal) {
    //   print('🚨 SIGINT received — triggering shutdown...');
    //   String message = "\$shutdown";
    //   final Pointer<Char> ptr = message.toNativeUtf8().cast<Char>();
    //   enqueueMessageFromDart(ptr, message.length);
    //   calloc.free(ptr);
    //   exit(0);
    // });

    print("Run end");
  }
}
