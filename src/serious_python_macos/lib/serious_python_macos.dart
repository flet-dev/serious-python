import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class SeriousPythonMacOS extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python_macos');

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonMacOS();
  }

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
    // if (environmentVariables != null) {
    //   for (var v in environmentVariables.entries) {
    //     await methodChannel.invokeMethod<String>(
    //         'setEnvironmentVariable', {'name': v.key, 'value': v.value});
    //   }
    // }

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

    runPythonProgramFFI(
        sync ?? false, "libpython3.10.so", pythonLibPath, appPath, [
      ...?modulePaths,
      "$pythonLibPath/modules",
      "$pythonLibPath/site-packages",
      "$pythonLibPath/stdlib.zip"
    ]);

    return null;
  }
}
