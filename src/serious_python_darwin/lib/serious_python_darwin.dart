import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

    return runPythonProgramFFI(
        sync ?? false,
        "${appContents.path}/Frameworks/Python.framework/Python",
        appPath,
        script ?? "");
  }
}
