import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/method_channel_serious_python.dart';

export 'src/dart_bridge_ffi.dart';
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

  /// Materializes the packaged app on disk (if needed) and returns the
  /// directory that contains its entry point (`main.pyc` / `main.py`).
  ///
  /// On desktop/iOS the app ships unpacked inside the application bundle, so
  /// this is a pure path lookup. On Android the app ships as a stored
  /// `app.zip` asset inside the APK and is unpacked once (version-keyed) to a
  /// writable files-dir location on the first launch after an install/update.
  Future<String> prepareApp() {
    throw UnimplementedError('prepareApp() has not been implemented.');
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
