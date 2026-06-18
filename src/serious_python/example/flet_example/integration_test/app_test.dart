import 'package:flet_example/main.dart' as app;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('make sure counter can be incremented and decremented',
        (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Wait for up to 10 seconds for the app to start
      bool counterFound = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));

        if (find.text('0').evaluate().isNotEmpty) {
          counterFound = true;
          break;
        }
      }

      expect(counterFound, isTrue);

      // Tap increment button
      await tester.tap(find.byKey(const Key('increment')));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // Tap decrement button
      await tester.tap(find.byKey(const Key('decrement')));
      await tester.tap(find.byKey(const Key('decrement')));
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsOneWidget);

      // Verify the bundled Python runtime matches what CI requested. Skipped
      // outside CI (no --dart-define).
      const expectedPyVersion =
          String.fromEnvironment('EXPECTED_PYTHON_VERSION');
      if (expectedPyVersion.isNotEmpty) {
        bool versionFound = false;
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(seconds: 1));
          if (find
              .textContaining('Python version: $expectedPyVersion.')
              .evaluate()
              .isNotEmpty) {
            versionFound = true;
            break;
          }
        }
        expect(versionFound, isTrue,
            reason:
                'Expected `Python version: $expectedPyVersion.x` in the app UI');
      }
    });
  });
}
