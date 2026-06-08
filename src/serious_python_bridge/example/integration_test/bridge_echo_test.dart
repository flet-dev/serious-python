import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serious_python/serious_python.dart';
import 'package:serious_python_bridge/serious_python_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('round-trips a 1KB random payload byte-identically', (tester) async {
    // Pump a minimal widget so Flutter binding + plugin registration
    // (including SeriousPythonBridgePlugin.register on iOS/macOS) runs.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final bridge = PythonBridge.init();
    addTearDown(bridge.dispose);

    // Fire-and-forget: Python's main.py blocks waiting for messages and never
    // returns; awaiting SeriousPython.run would deadlock the test.
    unawaited(SeriousPython.run('app/app.zip'));

    // Handshake: 8-byte little-endian native_port. Python echoes the same 8
    // bytes back once its on_dart_message handler is registered, which is our
    // readiness signal.
    final portBytes = Uint8List(8)
      ..buffer.asByteData().setInt64(0, bridge.nativePort, Endian.little);
    await _waitForHandshakeEcho(bridge, portBytes);

    // Round-trip a 1KB random buffer. Seed is fixed so repeated runs assert
    // against the same bytes — easier to debug a regression.
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
        .timeout(const Duration(seconds: 10));

    bridge.send(payload);

    final reply = await replyFuture;
    expect(reply, equals(expectedReply));
  });
}

Future<void> _waitForHandshakeEcho(
    PythonBridge bridge, Uint8List portBytes) async {
  const retryInterval = Duration(milliseconds: 500);
  const overallTimeout = Duration(seconds: 30);
  final deadline = DateTime.now().add(overallTimeout);

  while (DateTime.now().isBefore(deadline)) {
    final echoFuture = bridge.messages
        .firstWhere((b) => _bytesEqual(b, portBytes))
        .timeout(retryInterval);
    bridge.send(portBytes);
    try {
      await echoFuture;
      return;
    } on TimeoutException {
      // Python not ready yet — retry.
    }
  }
  throw TimeoutException(
      'Python did not echo handshake within ${overallTimeout.inSeconds}s');
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
