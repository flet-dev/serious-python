import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../serious_python_platform_interface.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class SeriousPythonIOS extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python');

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
    final Map<String, dynamic> arguments = {
      'appPath': appPath,
      'modulePaths': modulePaths,
      'environmentVariables': environmentVariables,
      'sync': sync
    };
    return await methodChannel.invokeMethod<String>('runPython', arguments);
  }
}
