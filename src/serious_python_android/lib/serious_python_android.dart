import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

import 'src/cpython.dart';

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

    // load libpyjni.so to get JNI reference
    try {
      await methodChannel
          .invokeMethod<String>('loadLibrary', {'libname': 'pyjni'});
      await setenv("FLET_JNI_READY", "1");
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

    var programDirPath = p.dirname(appPath);

    var moduleSearchPaths = [
      programDirPath,
      ...?modulePaths,
      "$pythonLibPath/modules",
      "$pythonLibPath/stdlib"
    ];

    if (await File(sitePackagesZipPath).exists()) {
      var sitePackagesPath = await extractFileZip(sitePackagesZipPath,
          targetPath: "python_site_packages");
      debugPrint("sitePackagesPath: $sitePackagesPath");
      moduleSearchPaths.add(sitePackagesPath);
    }

    setenv("PYTHONINSPECT", "1");
    setenv("PYTHONDONTWRITEBYTECODE", "1");
    setenv("PYTHONNOUSERSITE", "1");
    setenv("PYTHONUNBUFFERED", "1");
    setenv("LC_CTYPE", "UTF-8");
    setenv("PYTHONHOME", pythonLibPath);
    setenv("PYTHONPATH", moduleSearchPaths.join(":"));

    // set environment variables
    if (environmentVariables != null) {
      for (var v in environmentVariables.entries) {
        setenv(v.key, v.value);
      }
    }

    return runPythonProgramFFI(
        sync ?? false, "libpython3.12.so", appPath, script ?? "");
  }
}
