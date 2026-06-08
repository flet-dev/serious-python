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
    final bridge = PythonBridge.init();
    _subscription = bridge.messages.listen((bytes) {
      setState(() {
        _log.add('Python -> Dart: ${utf8.decode(bytes, allowMalformed: true)}');
      });
    });

    // Fire-and-forget; Python runs on a background thread and never returns
    // (its main.py blocks waiting for messages).
    unawaited(SeriousPython.run("app/app.zip"));

    // Crude: wait for Python to register its receive handler. A production
    // protocol would have Python send a "ready" sentinel and Dart wait for
    // that on bridge.messages before sending the handshake.
    await Future<void>.delayed(const Duration(seconds: 2));

    // Handshake: send the Dart ReceivePort native port id as the first frame.
    final portBytes = Uint8List(8);
    portBytes.buffer.asByteData().setInt64(0, bridge.nativePort, Endian.little);
    bridge.send(portBytes);

    setState(() {
      _bridge = bridge;
      _log.add('handshake sent (native_port=${bridge.nativePort})');
    });
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
