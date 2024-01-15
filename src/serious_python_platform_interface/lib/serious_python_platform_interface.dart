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

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) {
    throw UnimplementedError('run() has not been implemented.');
  }

  void terminate() {
    // nothing to do
  }
}
