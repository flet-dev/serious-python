import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/method_channel_serious_python.dart';

export 'src/utils.dart';

abstract class SeriousPythonPlatform extends PlatformInterface {
  /// Constructs a SeriousPythonPlatform.
  SeriousPythonPlatform() : super(token: _token);

  static final Object _token = Object();

  static SeriousPythonPlatform _instance = MethodChannelSeriousPython();

  /// The default instance of [SeriousPythonPlatform] to use.
  ///
  /// Defaults to [MethodChannelSeriousPython].
  static SeriousPythonPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SeriousPythonPlatform] when
  /// they register themselves.
  static set instance(SeriousPythonPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getDartBridgePath() {
    throw UnimplementedError('getDartBridgePath() has not been implemented.');
  }

  Future<List<String>?> getPythonModulePaths() {
    throw UnimplementedError(
        'getPythonModulePaths() has not been implemented.');
  }

  Future run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) {
    // do nothing
    return Future.value(null);
  }
}
