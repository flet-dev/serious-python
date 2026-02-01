import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

import 'src/cpython.dart';
import 'src/log.dart';

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
    Future<void> setenv(String key, String value) =>
        methodChannel.invokeMethod<String>(
            'setEnvironmentVariable', {'name': key, 'value': value});

    // load libpyjni.so to get JNI reference
    try {
      await methodChannel
          .invokeMethod<String>('loadLibrary', {'libname': 'pyjni'});
      await setenv("FLET_JNI_READY", "1");
    } catch (e) {
      spDebug("Unable to load libpyjni.so library: $e");
    }

    const pythonSharedLib = "libpython3.12.so";

    String? getPythonFullVersion() {
      try {
        final cpython = getCPython(pythonSharedLib);
        final versionPtr = cpython.Py_GetVersion();
        return versionPtr.cast<Utf8>().toDartString();
      } catch (e) {
        spDebug("Unable to read Python version for invalidation: $e");
        return null;
      }
    }

    Future<String?> getAppVersion() async {
      try {
        return await methodChannel.invokeMethod<String>('getAppVersion');
      } catch (e) {
        spDebug("Unable to get app version for invalidation: $e");
        return null;
      }
    }

    // unpack python bundle
    final nativeLibraryDir =
        await methodChannel.invokeMethod<String>('getNativeLibraryDir');
    spDebug("getNativeLibraryDir: $nativeLibraryDir");

    var bundlePath = "$nativeLibraryDir/libpythonbundle.so";
    var sitePackagesZipPath = "$nativeLibraryDir/libpythonsitepackages.so";

    if (!await File(bundlePath).exists()) {
      throw Exception("Python bundle not found: $bundlePath");
    }
    final pythonVersion = getPythonFullVersion();
    final pythonInvalidateKey =
        pythonVersion != null ? "python:$pythonVersion" : "python:$pythonSharedLib";
    var pythonLibPath = await extractFileZip(bundlePath,
        targetPath: "python_bundle", invalidateKey: pythonInvalidateKey);
    spDebug("pythonLibPath: $pythonLibPath");

    var programDirPath = p.dirname(appPath);

    var moduleSearchPaths = [
      programDirPath,
      ...?modulePaths,
      "$pythonLibPath/modules",
      "$pythonLibPath/stdlib"
    ];

    if (await File(sitePackagesZipPath).exists()) {
      final appVersion = await getAppVersion();
      final sitePackagesInvalidateKey =
          appVersion != null ? "app:$appVersion" : null;
      var sitePackagesPath = await extractFileZip(sitePackagesZipPath,
          targetPath: "python_site_packages",
          invalidateKey: sitePackagesInvalidateKey);
      spDebug("sitePackagesPath: $sitePackagesPath");
      moduleSearchPaths.add(sitePackagesPath);
    }

    await setenv("PYTHONINSPECT", "1");
    await setenv("PYTHONDONTWRITEBYTECODE", "1");
    await setenv("PYTHONNOUSERSITE", "1");
    await setenv("PYTHONUNBUFFERED", "1");
    await setenv("LC_CTYPE", "UTF-8");
    await setenv("PYTHONHOME", pythonLibPath);
    await setenv("PYTHONPATH", moduleSearchPaths.join(":"));

    // set environment variables
    if (environmentVariables != null) {
      for (var v in environmentVariables.entries) {
        await setenv(v.key, v.value);
      }
    }

    return runPythonProgramFFI(
        sync ?? false, pythonSharedLib, appPath, script ?? "");
  }
}
