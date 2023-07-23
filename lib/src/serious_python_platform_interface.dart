import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'android/serious_python_android.dart';
import 'ios/serious_python_ios.dart';

abstract class SeriousPythonPlatform extends PlatformInterface {
  /// Constructs a SeriousPythonPlatform.
  SeriousPythonPlatform() : super(token: _token);

  static final Object _token = Object();

  static SeriousPythonPlatform? _instance;

  /// The default instance of [SeriousPythonPlatform] to use.
  ///
  /// Defaults to [SeriousPythonIOS].
  static SeriousPythonPlatform get instance {
    if (_instance == null) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _instance = SeriousPythonIOS();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        _instance = SeriousPythonAndroid();
      } else {
        throw UnimplementedError(
            '$defaultTargetPlatform platform is not supported yet.');
      }
    }
    return _instance!;
  }

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
      {List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) {
    throw UnimplementedError('run() has not been implemented.');
  }
}
