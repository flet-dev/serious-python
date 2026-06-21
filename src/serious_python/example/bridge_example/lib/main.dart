import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:serious_python/bridge.dart';
import 'package:serious_python/serious_python.dart';

/// Env-var names carrying the Dart-side native ports to Python. The bridge
/// library doesn't bake in a convention — the example picks names and Python
/// reads them from os.environ.
const _controlPortEnv = 'BRIDGE_EXAMPLE_CONTROL_PORT';
const _echoPortEnv = 'BRIDGE_EXAMPLE_ECHO_PORT';

/// Top-level handle exposing the two bridges + the latest counter/version to
/// integration tests, so they can interact with the transport without traversing
/// the widget tree. Populated by `main()` once both bridges are constructed.
class BridgeExampleHandle {
  BridgeExampleHandle._(this.controlBridge, this.echoBridge);

  static BridgeExampleHandle? _instance;
  static BridgeExampleHandle get instance {
    final v = _instance;
    if (v == null) {
      throw StateError(
          'BridgeExampleHandle not initialised — main() must run first');
    }
    return v;
  }

  final PythonBridge controlBridge;
  final PythonBridge echoBridge;

  /// Current counter value (updated when Python emits {event: count}).
  final ValueNotifier<int> counter = ValueNotifier<int>(0);

  /// Python version string, e.g. "3.14.6". `null` until the first `version`
  /// event arrives.
  final ValueNotifier<String?> pythonVersion = ValueNotifier<String?>(null);

  /// Send a JSON control op (Dart → Python) on the control channel.
  void sendControl(Map<String, dynamic> op) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(op)));
    if (controlBridge.send(bytes)) return;
    _retrySend(controlBridge, bytes);
  }

  /// Brief retry to cover the startup window where Python's handler hasn't
  /// registered yet. Matches the pattern in flet's build template
  /// (`_DartBridgeBackendChannel._retrySend`).
  static void _retrySend(PythonBridge bridge, Uint8List bytes) {
    const interval = Duration(milliseconds: 50);
    const deadline = Duration(seconds: 30);
    final start = DateTime.now();
    Timer.periodic(interval, (timer) {
      if (bridge.send(bytes)) {
        timer.cancel();
      } else if (DateTime.now().difference(start) > deadline) {
        timer.cancel();
        debugPrint(
            '[bridge_example] send timed out — Python handler never registered');
      }
    });
  }
}

void main() {
  // Bridges live for the app's lifetime; constructed before runApp so the
  // testable handle is available immediately.
  final control = PythonBridge();
  final echo = PythonBridge();
  BridgeExampleHandle._instance =
      BridgeExampleHandle._(control, echo);

  // Fire-and-forget: Python's main.py blocks forever waiting for messages.
  // Awaiting SeriousPython.run() would deadlock the UI.
  unawaited(SeriousPython.run(
    environmentVariables: {
      _controlPortEnv: '${control.port}',
      _echoPortEnv: '${echo.port}',
    },
  ));

  runApp(const BridgeExampleApp());
}

class BridgeExampleApp extends StatefulWidget {
  const BridgeExampleApp({super.key});

  @override
  State<BridgeExampleApp> createState() => _BridgeExampleAppState();
}

class _BridgeExampleAppState extends State<BridgeExampleApp> {
  StreamSubscription<Uint8List>? _controlSub;
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    final handle = BridgeExampleHandle.instance;
    _controlSub = handle.controlBridge.messages.listen(_onControl);

    // Request the Python version once Python has had a moment to register
    // its handler. sendControl() retries internally if the handler isn't
    // ready yet, so we can fire immediately.
    handle.sendControl({'op': 'version'});
    _log.add('control_port=${handle.controlBridge.port} '
        'echo_port=${handle.echoBridge.port}');
  }

  void _onControl(Uint8List bytes) {
    final handle = BridgeExampleHandle.instance;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[bridge_example] control parse error: $e');
      return;
    }
    final event = msg['event'];
    if (event == 'count') {
      handle.counter.value = msg['value'] as int;
    } else if (event == 'version') {
      handle.pythonVersion.value = msg['value'] as String;
    }
    // 'mem' events are consumed by the memory test directly via its own
    // listener — no widget-visible state for them.
    setState(() => _log.add('Python -> Dart: ${msg.toString()}'));
  }

  @override
  void dispose() {
    _controlSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = BridgeExampleHandle.instance;
    return MaterialApp(
      title: 'bridge_example',
      home: Scaffold(
        appBar: AppBar(title: const Text('PythonBridge example')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('decrement'),
                    icon: const Icon(Icons.remove),
                    onPressed: () => handle.sendControl({'op': 'dec'}),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: handle.counter,
                    builder: (_, value, __) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '$value',
                        key: const Key('counter'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('increment'),
                    icon: const Icon(Icons.add),
                    onPressed: () => handle.sendControl({'op': 'inc'}),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: handle.pythonVersion,
              builder: (_, version, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  version == null
                      ? 'Python version: …'
                      : 'Python version: $version',
                  key: const Key('version'),
                ),
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
