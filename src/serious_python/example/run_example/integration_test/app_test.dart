import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:run_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('tap on the floating action button, verify counter',
        (tester) async {
      // Load app widget.
      await tester.pumpWidget(const MyApp());

      // Verify the initial state is "Running..."
      expect(find.text('Running...'), findsOneWidget);

      // Wait for up to 10 seconds for the text to change to "PASS"
      bool textChanged = false;
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));

        if (find.text('PASS').evaluate().isNotEmpty) {
          textChanged = true;
          break;
        }
      }

      // Verify the text has changed to "PASS"
      expect(textChanged, isTrue);
    });
  });
}
