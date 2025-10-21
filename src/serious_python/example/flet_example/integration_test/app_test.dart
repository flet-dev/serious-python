import 'package:flet_example/main.dart' as app;
import 'package:flutter/foundation.dart';
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
      final incrementButton = find.byKey(const Key('increment'));
      await tester.tap(incrementButton);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // Tap decrement button
      final decrementButton = find.byKey(const Key('decrement'));
      await tester.tap(decrementButton);
      await tester.tap(decrementButton);
      await tester.pumpAndSettle();
      expect(find.text('-1'), findsOneWidget);
    });
  });
}
