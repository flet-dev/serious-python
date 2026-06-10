import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// An in-process Dart ↔ Python byte channel, backed by the `dart_bridge`
/// native library.
///
/// Each [PythonBridge] owns a [ReceivePort] whose native port doubles as the
/// channel key in both directions:
///
/// - Python → Dart: when Python calls `dart_bridge.send_bytes(port, payload)`,
///   the payload arrives on this bridge's [messages] stream.
/// - Dart → Python: [send] hands bytes to the Python handler registered for
///   this port via `dart_bridge.set_enqueue_handler_func(port, handler)`.
///
/// Multiple bridges (UI channel, logging channel, future camera-stream
/// channel, ...) can coexist in a single app — each bridge has its own port
/// and its own Python-side handler.
///
/// Typical use:
///
/// ```dart
/// final ui   = PythonBridge();
/// final logs = PythonBridge();
///
/// ui.messages.listen((Uint8List bytes) { /* UI events */ });
/// logs.messages.listen((Uint8List bytes) { /* log lines */ });
///
/// await SeriousPython.run('app/main.py', environmentVariables: {
///   'MY_APP_UI_PORT':   '${ui.port}',
///   'MY_APP_LOGS_PORT': '${logs.port}',
/// });
///
/// ui.send(Uint8List.fromList([1, 2, 3]));
/// ```
///
/// The Python side reads the chosen env-var names to discover its port
/// numbers — no convention is baked in here.
class PythonBridge {
  PythonBridge() {
    _bridge = DartBridge.instance;
    _bridge.initDartApiDL();
    _rx.listen(_onMessage);
  }

  final ReceivePort _rx = ReceivePort();
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();
  late final DartBridge _bridge;
  bool _closed = false;

  /// Dart native port acting as this channel's key. Pass it to the Python
  /// program (typically via an environment variable) so Python knows where
  /// to send messages and which port to register its handler under.
  int get port => _rx.sendPort.nativePort;

  /// Bytes pushed by Python via `dart_bridge.send_bytes(port, payload)`.
  Stream<Uint8List> get messages => _messages.stream;

  /// Send [bytes] to the Python handler registered for this bridge's [port].
  ///
  /// Returns `true` on successful delivery, `false` if no Python handler is
  /// currently registered for this port (typical reason: Python hasn't yet
  /// called `dart_bridge.set_enqueue_handler_func`). The caller may retry.
  ///
  /// Throws [StateError] if the Python interpreter is not running.
  bool send(Uint8List bytes) {
    if (_closed) {
      throw StateError('PythonBridge is closed');
    }
    final len = bytes.length;
    final buf = malloc<Uint8>(len == 0 ? 1 : len);
    try {
      if (len > 0) {
        buf.asTypedList(len).setAll(0, bytes);
      }
      final rc = _bridge.enqueueMessage(port, buf, len);
      if (rc == -2) {
        throw StateError('Python interpreter is not initialized');
      }
      return rc == 0;
    } finally {
      malloc.free(buf);
    }
  }

  /// Release this bridge's ReceivePort. After closing, [send] throws and the
  /// [messages] stream emits done.
  void close() {
    if (_closed) return;
    _closed = true;
    _rx.close();
    _messages.close();
  }

  void _onMessage(dynamic message) {
    if (message is Uint8List) {
      _messages.add(message);
    } else if (message is List<int>) {
      _messages.add(Uint8List.fromList(message));
    }
    // Drop unexpected message shapes silently — the Python side only ever
    // posts typed-data via Dart_PostCObject_DL.
  }
}
