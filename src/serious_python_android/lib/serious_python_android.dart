import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String? _dartBridgePath;
  List<String>? _pythonModulePaths;

  @override
  Future<String?> getDartBridgePath() {
    return Future.value(_dartBridgePath);
  }

  @override
  Future<List<String>?> getPythonModulePaths() async {
    return Future.value(_pythonModulePaths);
  }

  @override
  Future run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    // load libpyjni.so to get JNI reference
    try {
      await methodChannel
          .invokeMethod<String>('loadLibrary', {'libname': 'pyjni'});
      //await setenv("FLET_JNI_READY", "1");
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

    _pythonModulePaths = ["$pythonLibPath/modules", "$pythonLibPath/stdlib"];

    if (await File(sitePackagesZipPath).exists()) {
      var sitePackagesPath = await extractFileZip(sitePackagesZipPath,
          targetPath: "python_site_packages");
      debugPrint("sitePackagesPath: $sitePackagesPath");
      _pythonModulePaths?.add(sitePackagesPath);

      final soFile =
          Directory(sitePackagesPath).listSync().whereType<File>().firstWhere(
                (f) => f.path.contains(RegExp(r'dart_bridge.*\.so$')),
                orElse: () => File(''),
              );
      _dartBridgePath = await soFile.exists() ? soFile.path : null;
    }
  }
}
