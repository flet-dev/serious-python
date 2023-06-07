import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:serious_python/serious_python.dart';
import 'package:serious_python/src/serious_python_method_channel.dart';
import 'package:serious_python/src/serious_python_platform_interface.dart';

class MockSeriousPythonPlatform
    with MockPlatformInterfaceMixin
    implements SeriousPythonPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> run(String appPath,
      {List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) {
    throw UnimplementedError();
  }
}

void main() {
  final SeriousPythonPlatform initialPlatform = SeriousPythonPlatform.instance;

  test('$MethodChannelSeriousPython is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSeriousPython>());
  });

  test('getPlatformVersion', () async {
    SeriousPython seriousPythonPlugin = SeriousPython();
    MockSeriousPythonPlatform fakePlatform = MockSeriousPythonPlatform();
    SeriousPythonPlatform.instance = fakePlatform;

    expect(await seriousPythonPlugin.getPlatformVersion(), '42');
  });
}
