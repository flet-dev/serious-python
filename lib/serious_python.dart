import 'serious_python_platform_interface.dart';

class SeriousPython {
  Future<String?> getPlatformVersion() {
    return SeriousPythonPlatform.instance.getPlatformVersion();
  }

  Future<String?> runPython(String appPath,
      {List<String>? modulePaths, Map<String, String>? environmentVariables}) {
    return SeriousPythonPlatform.instance.runPython(appPath,
        modulePaths: modulePaths, environmentVariables: environmentVariables);
  }
}
