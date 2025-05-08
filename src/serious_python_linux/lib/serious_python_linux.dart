import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

class SeriousPythonLinux extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python_linux');

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonLinux();
  }

  @override
  Future<PythonEnvironment> setupPythonEnvironment(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables}) async {
    var exePath = Platform.resolvedExecutable;
    var exeDir = Directory(exePath).parent.path;
    var sitePackagesPath = path.join(exeDir, "site-packages");

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

    return PythonEnvironment(
        dartBridgeLibraryPath: soFile.path,
        modulePaths: [sitePackagesPath, path.join(exeDir, "python3.12")]);
  }
}
