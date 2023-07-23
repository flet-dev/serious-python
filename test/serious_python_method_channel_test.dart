import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serious_python/src/ios/serious_python_ios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SeriousPythonIOS platform = SeriousPythonIOS();
  const MethodChannel channel = MethodChannel('serious_python');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
