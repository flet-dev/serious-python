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
  Future<String?> getDartBridgePath() {
    return methodChannel.invokeMethod<String>('getDartBridgePath');
  }

  @override
  Future<List<String>?> getPythonModulePaths() async {
    return (await methodChannel.invokeMethod('getPythonModulePaths'))
        .cast<String>();
  }
}
