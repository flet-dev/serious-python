import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:serious_python/serious_python.dart';
import 'package:serious_python_bridge/serious_python_bridge.dart';

void main() {
  runApp(const BridgeExampleApp());
}

class BridgeExampleApp extends StatefulWidget {
  const BridgeExampleApp({super.key});

  @override
  State<BridgeExampleApp> createState() => _BridgeExampleAppState();
}

class _BridgeExampleAppState extends State<BridgeExampleApp> {
  PythonBridge? _bridge;
  StreamSubscription<Uint8List>? _subscription;
  final List<String> _log = <String>[];
  int _sendCounter = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    debugPrint('[bridge_example] _start: initializing bridge');
    final bridge = PythonBridge.init();
    debugPrint('[bridge_example] bridge.nativePort=${bridge.nativePort}');
    _subscription = bridge.messages.listen((bytes) {
      debugPrint('[bridge_example] received ${bytes.length} bytes from Python');
      setState(() {
        _log.add('Python -> Dart: ${utf8.decode(bytes, allowMalformed: true)}');
      });
    });

    // Fire-and-forget; Python runs on a background thread and never returns
    // (its main.py blocks waiting for messages).
    debugPrint('[bridge_example] starting Python via SeriousPython.run');
    unawaited(SeriousPython.run("app/app.zip"));

    // Retry the handshake until Python echoes it back — Dart's first send may
    // arrive before main.py has called set_enqueue_handler_func, and the
    // bridge silently drops messages when no handler is registered.
    final portBytes = Uint8List(8)
      ..buffer.asByteData().setInt64(0, bridge.nativePort, Endian.little);
    debugPrint('[bridge_example] starting handshake retry');
    await _handshakeUntilReady(bridge, portBytes);
    debugPrint('[bridge_example] handshake complete');

    setState(() {
      _bridge = bridge;
      _log.add('handshake complete (native_port=${bridge.nativePort})');
    });
  }

  Future<void> _handshakeUntilReady(
      PythonBridge bridge, Uint8List portBytes) async {
    const retryInterval = Duration(milliseconds: 500);
    const overallTimeout = Duration(seconds: 30);
    final deadline = DateTime.now().add(overallTimeout);

    while (DateTime.now().isBefore(deadline)) {
      // Subscribe FIRST so a fast Python echo isn't missed — bridge.messages
      // is a broadcast stream and doesn't replay past emissions.
      final echoFuture = bridge.messages
          .firstWhere((b) =>
              b.length == portBytes.length && _bytesEqual(b, portBytes))
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
        'Python did not echo the handshake within ${overallTimeout.inSeconds}s');
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _sendTestMessage() {
    final bridge = _bridge;
    if (bridge == null) return;
    _sendCounter++;
    final payload = utf8.encode('ping #$_sendCounter');
    bridge.send(Uint8List.fromList(payload));
    setState(() => _log.add('Dart -> Python: ping #$_sendCounter'));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'serious_python_bridge example',
      home: Scaffold(
        appBar: AppBar(title: const Text('serious_python_bridge example')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                key: const Key('send'),
                onPressed: _bridge != null ? _sendTestMessage : null,
                child: const Text('Send ping to Python'),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, index) => ListTile(
                  dense: true,
                  title: Text(
                    _log[index],
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
