import 'dart:ffi';
import 'dart:io';

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
      bool? sync}) async {
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
        userModulePaths: modulePaths,
        userEnvironmentVariables: environmentVariables,
        script: Platform.isWindows ? "" : null,
        sync: sync);
  }

  /// Runs Python program from a path.
  ///
  /// This is low-level method.
  /// Make sure `Directory.current` is set before calling this method.
  ///
  /// [appPath] is the full path to a .py or .pyc file to run.
  ///
  /// Environment variables that must be available to a Python program could
  /// be passed in [userEnvironmentVariables].
  ///
  /// By default, Serious Python expects Python dependencies installed into
  /// `__pypackages__` directory in the root of app directory. Additional paths
  /// to look for 3rd-party packages can be specified with [userModulePaths] parameter.
  ///
  /// Set [sync] to `true` to sychronously run Python program; otherwise the
  /// program starts in a new thread.
  static Future runProgram(String appPath,
      {String? script,
      List<String>? userModulePaths,
      Map<String, String>? userEnvironmentVariables,
      bool? sync}) async {
    // run before run python program
    var pythonEnvironment = await SeriousPythonPlatform.instance
        .setupPythonEnvironment(appPath,
            script: script,
            modulePaths: userModulePaths,
            environmentVariables: userEnvironmentVariables);

    // run python program with FFI
    _cpython =
        CPython(DynamicLibrary.open(pythonEnvironment.dartBridgeLibraryPath));

    var programDirPath = path.dirname(appPath);

    // all environment variables
    Map<String, String> envVars = Map.from(userEnvironmentVariables ?? {});
    envVars["PYTHONINSPECT"] = "1";
    envVars["PYTHONDONTWRITEBYTECODE"] = "1";
    envVars["PYTHONNOUSERSITE"] = "1";
    envVars["PYTHONUNBUFFERED"] = "1";
    envVars["LC_CTYPE"] = "UTF-8";
    envVars["PYTHONHOME"] = programDirPath;

    if (pythonEnvironment.environmentVariables != null) {
      for (var v in pythonEnvironment.environmentVariables!.entries) {
        envVars[v.key] = v.value;
      }
    }

    // all module paths
    List<String> allModulePaths = [
      programDirPath,
      "$programDirPath/__pypackages__",
      ...?userModulePaths,
      ...?pythonEnvironment.modulePaths,
    ];

    // run Python program or script
    _cpython!.runPython(
        appPath: appPath,
        script: script ?? "",
        modules: allModulePaths,
        envVars: envVars,
        sync: sync ?? false);
  }

  static sendMessageToPython(Uint8List message) {
    if (_cpython == null) {
      throw Exception("Python program is not running.");
    }
    _cpython!.sendMessageToPython(message);
  }
}
