import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../serious_python_platform_interface.dart';

/// An implementation of [SeriousPythonPlatform] that uses method channels.
class MethodChannelSeriousPython extends SeriousPythonPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python');

  @override
  Future<String?> getDartBridgePath() {
    return methodChannel.invokeMethod<String>('getDartBridgePath');
  }

  @override
  Future<List<String>?> getPythonModulePaths() {
    return methodChannel.invokeMethod<List<String>>('getPythonModulePaths');
  }
}
