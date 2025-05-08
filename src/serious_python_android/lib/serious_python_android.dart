import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class SeriousPythonAndroid extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('android_plugin');

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonAndroid();
  }

  @override
  Future<PythonEnvironment> setupPythonEnvironment(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables}) async {
    Map<String, String> envVars = {};
    // load libpyjni.so to get JNI reference
    try {
      await methodChannel
          .invokeMethod<String>('loadLibrary', {'libname': 'pyjni'});
      envVars["FLET_JNI_READY"] = "1";
    } catch (e) {
      debugPrint("Warning: Unable to load libpyjni.so library: $e");
    }

    // unpack python bundle
    final nativeLibraryDir =
        await methodChannel.invokeMethod<String>('getNativeLibraryDir');
    debugPrint("getNativeLibraryDir: $nativeLibraryDir");

    var bundlePath = "$nativeLibraryDir/libpythonbundle.so";
    var sitePackagesZipPath = "$nativeLibraryDir/libpythonsitepackages.so";

    if (!await File(bundlePath).exists()) {
      throw Exception("Python bundle not found: $bundlePath");
    }
    var pythonLibPath =
        await extractFileZip(bundlePath, targetPath: "python_bundle");
    debugPrint("pythonLibPath: $pythonLibPath");

    var pythonModulePaths = ["$pythonLibPath/modules", "$pythonLibPath/stdlib"];
    String? dartBridgeLibraryPath;

    if (await File(sitePackagesZipPath).exists()) {
      var sitePackagesPath = await extractFileZip(sitePackagesZipPath,
          targetPath: "python_site_packages");
      debugPrint("sitePackagesPath: $sitePackagesPath");
      pythonModulePaths.add(sitePackagesPath);

      var soFile = Directory(sitePackagesPath)
          .listSync()
          .whereType<File>()
          .where((file) =>
              path.basename(file.path).startsWith("dart_bridge.") &&
              path.basename(file.path).endsWith(".so"))
          .firstOrNull;
      if (soFile == null) {
        throw Exception(
            "dart_bridge.*.so library is not found in $sitePackagesPath");
      }
      dartBridgeLibraryPath = soFile.path;
    } else {
      throw Exception("App bundle does not contain site-packages.");
    }

    return PythonEnvironment(
        dartBridgeLibraryPath: dartBridgeLibraryPath,
        modulePaths: pythonModulePaths,
        environmentVariables: envVars);
  }
}
