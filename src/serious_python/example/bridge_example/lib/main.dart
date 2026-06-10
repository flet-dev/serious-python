import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:serious_python/bridge.dart';
import 'package:serious_python/serious_python.dart';

/// Env-var name carrying the Dart-side native port to Python. The bridge
/// library doesn't bake in a convention — the example picks one and Python
/// reads it from os.environ by the same name.
const _bridgePortEnv = 'BRIDGE_EXAMPLE_PORT';

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
    final bridge = PythonBridge();
    debugPrint('[bridge_example] bridge.port=${bridge.port}');
    _subscription = bridge.messages.listen((bytes) {
      setState(() {
        _log.add('Python -> Dart: ${utf8.decode(bytes, allowMalformed: true)}');
      });
    });

    // Fire-and-forget: Python's main.py blocks waiting for messages and never
    // returns. Awaiting SeriousPython.run() would deadlock the UI.
    unawaited(SeriousPython.run(
      'app/app.zip',
      environmentVariables: {_bridgePortEnv: '${bridge.port}'},
    ));

    setState(() {
      _bridge = bridge;
      _log.add('bridge ready (port=${bridge.port})');
    });
  }

  void _sendTestMessage() {
    final bridge = _bridge;
    if (bridge == null) return;
    _sendCounter++;
    final payload = utf8.encode('ping #$_sendCounter');
    final delivered = bridge.send(Uint8List.fromList(payload));
    setState(() => _log.add(
        'Dart -> Python: ping #$_sendCounter${delivered ? '' : ' (no handler yet)'}'));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bridge_example',
      home: Scaffold(
        appBar: AppBar(title: const Text('PythonBridge example')),
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
