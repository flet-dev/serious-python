import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('counter responds to inc/dec via control channel',
      (tester) async {
    final handle = await bootAndAwaitReady(tester);
    expect(find.byKey(const Key('counter')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    // Increment once: Python returns {event: count, value: 1}.
    await tester.tap(find.byKey(const Key('increment')));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    // Decrement twice: 1 -> 0 -> -1.
    await tester.tap(find.byKey(const Key('decrement')));
    await tester.tap(find.byKey(const Key('decrement')));
    await tester.pumpAndSettle();
    expect(find.text('-1'), findsOneWidget);

    // Optional version assertion: only when the test harness passes
    // EXPECTED_PYTHON_VERSION (CI does; local runs may not).
    const expected = String.fromEnvironment('EXPECTED_PYTHON_VERSION');
    if (expected.isNotEmpty) {
      expect(handle.pythonVersion.value, isNotNull);
      expect(handle.pythonVersion.value, startsWith('$expected.'));
      expect(
        find.text('Python version: ${handle.pythonVersion.value}'),
        findsOneWidget,
      );
    }
  });
}
