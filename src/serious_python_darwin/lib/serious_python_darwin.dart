import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    final Map<String, dynamic> arguments = {
      'appPath': appPath,
      'script': script,
      'modulePaths': modulePaths,
      'environmentVariables': environmentVariables,
      'sync': sync
    };
    return await methodChannel.invokeMethod<String>('runPython', arguments);
  }
}
