import 'package:plugin_platform_interface/plugin_platform_interface.dart';

export 'src/utils.dart';

class PythonEnvironment {
  String dartBridgeLibraryPath;
  List<String>? modulePaths;
  Map<String, String>? environmentVariables;

  PythonEnvironment(
      {required this.dartBridgeLibraryPath,
      this.modulePaths,
      this.environmentVariables});
}

/// An implementation of [SeriousPythonPlatform] that does nothing.
class UnimplementedSeriousPythonPlatform extends SeriousPythonPlatform {}

abstract class SeriousPythonPlatform extends PlatformInterface {
  /// Constructs a SeriousPythonPlatform.
  SeriousPythonPlatform() : super(token: _token);

  static final Object _token = Object();

  static SeriousPythonPlatform _instance = UnimplementedSeriousPythonPlatform();

  /// The default instance of [SeriousPythonPlatform] to use.
  ///
  /// Defaults to [UnimplementedSeriousPythonPlatform].
  static SeriousPythonPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SeriousPythonPlatform] when
  /// they register themselves.
  static set instance(SeriousPythonPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<PythonEnvironment> setupPythonEnvironment(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables}) {
    throw UnimplementedError(
        "setupPythonEnvironment() has not been implemented.");
  }
}
