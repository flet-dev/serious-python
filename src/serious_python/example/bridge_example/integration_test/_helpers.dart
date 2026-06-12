import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bridge_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:serious_python/bridge.dart';

/// Boot the host app and wait for both PythonBridge channels to be ready
/// (i.e. for Python to have registered its handlers via
/// `dart_bridge.set_enqueue_handler_func`). Once this returns, [sendControl]
/// and `echoRoundTrip` will succeed without retry overhead.
Future<app.BridgeExampleHandle> bootAndAwaitReady(WidgetTester tester) async {
  app.main();
  // Give Flutter + Python a beat. Python starts on a worker thread and
  // registers handlers before its `threading.Event().wait()` parks.
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final handle = app.BridgeExampleHandle.instance;

  // Wait for the version event main() requested during initState. It only
  // arrives after Python's handler is registered, so it's a natural
  // readiness signal for the control channel.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (handle.pythonVersion.value == null) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
          'Python control handler never responded with version event');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Probe the echo channel separately — handlers register independently and
  // there's no inherent ordering guarantee.
  await _probeEchoReady(handle.echoBridge);
  return handle;
}

Future<void> _probeEchoReady(PythonBridge echo) async {
  final probe = Uint8List.fromList(<int>[0x00, 0x42]);
  final reply = echo.messages
      .firstWhere((b) => b.length == probe.length)
      .timeout(const Duration(seconds: 30));
  const interval = Duration(milliseconds: 100);
  const deadline = Duration(seconds: 30);
  final start = DateTime.now();
  while (true) {
    if (echo.send(probe)) break;
    if (DateTime.now().difference(start) > deadline) {
      throw TimeoutException(
          'Python echo handler never registered after $deadline');
    }
    await Future<void>.delayed(interval);
  }
  await reply;
}

/// Send a JSON control op (Dart→Python).
void sendControl(app.BridgeExampleHandle handle, Map<String, dynamic> op) {
  handle.sendControl(op);
}

/// Wait for the next control frame with `event == name`, JSON-decoded.
Future<Map<String, dynamic>> waitControlEvent(
  app.BridgeExampleHandle handle,
  String name, {
  Duration timeout = const Duration(seconds: 5),
}) {
  return handle.controlBridge.messages
      .map((b) => jsonDecode(utf8.decode(b)) as Map<String, dynamic>)
      .firstWhere((msg) => msg['event'] == name)
      .timeout(timeout);
}

/// One-shot echo round-trip: send `payload`, await the next frame whose
/// length matches, return it. No opcode parsing — the echo channel speaks
/// raw bytes only.
Future<Uint8List> echoRoundTrip(
  app.BridgeExampleHandle handle,
  Uint8List payload, {
  Duration timeout = const Duration(seconds: 30),
}) {
  final reply = handle.echoBridge.messages
      .firstWhere((b) => b.length == payload.length)
      .timeout(timeout);
  if (!handle.echoBridge.send(payload)) {
    return Future.error(StateError(
        'echo bridge handler not registered — call bootAndAwaitReady first'));
  }
  return reply;
}

/// Memory snapshot from the Python side (rss in bytes; tracemalloc current
/// and peak in bytes). Convenience wrapper over `sendControl({'op': 'mem'})`
/// + `waitControlEvent('mem')`.
class MemSnapshot {
  MemSnapshot({
    required this.rss,
    required this.tracedCurrent,
    required this.tracedPeak,
  });
  final int rss;
  final int tracedCurrent;
  final int tracedPeak;

  @override
  String toString() =>
      'MemSnapshot(rss=$rss, traced_current=$tracedCurrent, traced_peak=$tracedPeak)';
}

Future<MemSnapshot> memSnapshot(app.BridgeExampleHandle handle) async {
  final fut = waitControlEvent(handle, 'mem',
      timeout: const Duration(seconds: 10));
  handle.sendControl({'op': 'mem'});
  final msg = await fut;
  return MemSnapshot(
    rss: msg['rss'] as int,
    tracedCurrent: msg['traced_current'] as int,
    tracedPeak: msg['traced_peak'] as int,
  );
}
