import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serious_python/bridge.dart';
import 'package:serious_python/serious_python.dart';

/// Env-var name carrying the Dart-side native port to Python. Must match the
/// name read by `app/src/main.py`.
const _bridgePortEnv = 'BRIDGE_EXAMPLE_PORT';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('round-trips a 1KB random payload byte-identically',
      (tester) async {
    // Pump a minimal widget so the Flutter binding + native plugin
    // registration runs before we touch FFI.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final bridge = PythonBridge();
    addTearDown(bridge.close);

    // Fire-and-forget: Python's main.py blocks waiting for messages and never
    // returns. The port reaches Python via the env var — no in-band handshake.
    unawaited(SeriousPython.run(
      'app/app.zip',
      environmentVariables: {_bridgePortEnv: '${bridge.port}'},
    ));

    // Round-trip a 1KB random buffer. Seed is fixed so repeated runs assert
    // against the same bytes — easier to debug regressions.
    final rng = Random(0xC0FFEE);
    final payload = Uint8List.fromList(
      List<int>.generate(1024, (_) => rng.nextInt(256)),
    );
    final expectedPrefix = Uint8List.fromList('echo: '.codeUnits);
    final expectedReply = Uint8List(expectedPrefix.length + payload.length)
      ..setRange(0, expectedPrefix.length, expectedPrefix)
      ..setRange(expectedPrefix.length, expectedPrefix.length + payload.length,
          payload);

    // Pre-subscribe to the echo before sending.
    final replyFuture = bridge.messages
        .firstWhere((b) => b.length == expectedReply.length)
        .timeout(const Duration(seconds: 30));

    // Python may not have registered its handler yet; retry until it does.
    await _sendUntilDelivered(bridge, payload);

    final reply = await replyFuture;
    expect(reply, equals(expectedReply));
  });
}

Future<void> _sendUntilDelivered(PythonBridge bridge, Uint8List payload) async {
  const retryInterval = Duration(milliseconds: 200);
  const overallTimeout = Duration(seconds: 30);
  final deadline = DateTime.now().add(overallTimeout);

  while (DateTime.now().isBefore(deadline)) {
    if (bridge.send(payload)) return;
    await Future<void>.delayed(retryInterval);
  }
  throw TimeoutException(
      'Python did not register a handler within ${overallTimeout.inSeconds}s');
}
