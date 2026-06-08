import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _DartBridgeInitNative = IntPtr Function(Pointer<Void>);
typedef _DartBridgeInit = int Function(Pointer<Void>);

typedef _DartBridgeEnqueueNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _DartBridgeEnqueue = void Function(Pointer<Uint8>, int);

/// Generic in-process Dart ↔ Python byte transport.
///
/// Wraps the native `dart_bridge` C symbols (`DartBridge_InitDartApiDL`,
/// `DartBridge_EnqueueMessage`, and the corresponding Python-side
/// `dart_bridge.send_bytes`) into an idiomatic Dart API:
///
/// * `messages` — broadcast stream of byte buffers posted from Python.
/// * `send(bytes)` — push bytes to Python (synchronous; acquires the GIL).
/// * `nativePort` — the Dart native port id Python uses to post back; the
///   caller is responsible for handing this id to Python in whatever way its
///   protocol requires (typically as the first frame).
///
/// The bridge is process-global state (Python's `global_enqueue_handler_func`
/// and Dart's API-DL initialization are both singletons), so this class is
/// implemented as a singleton. `PythonBridge.init()` is idempotent.
///
/// Threading: `send()` blocks the calling thread for the duration of the
/// Python handler dispatch (which runs synchronously under `PyGILState_Ensure`).
/// To avoid stalling Flutter UI frames, call `send()` from a dedicated isolate
/// rather than the root isolate.
class PythonBridge {
  PythonBridge._();

  static PythonBridge? _instance;

  late final DynamicLibrary _lib;
  late final _DartBridgeInit _initDartApiDL;
  late final _DartBridgeEnqueue _enqueueMessage;

  late final ReceivePort _receivePort;
  final StreamController<Uint8List> _messages =
      StreamController<Uint8List>.broadcast();

  /// Returns the singleton bridge instance, initializing it on first call.
  factory PythonBridge.init() {
    final existing = _instance;
    if (existing != null) return existing;
    final bridge = PythonBridge._().._initialize();
    _instance = bridge;
    return bridge;
  }

  /// The currently initialized bridge, or `null` if `init()` hasn't been called.
  static PythonBridge? get instance => _instance;

  void _initialize() {
    _lib = _openNativeLibrary();

    _initDartApiDL = _lib
        .lookup<NativeFunction<_DartBridgeInitNative>>('DartBridge_InitDartApiDL')
        .asFunction();
    _enqueueMessage = _lib
        .lookup<NativeFunction<_DartBridgeEnqueueNative>>('DartBridge_EnqueueMessage')
        .asFunction();

    if (_initDartApiDL(NativeApi.initializeApiDLData) != 0) {
      throw StateError(
          'DartBridge_InitDartApiDL failed: Dart VM API version mismatch');
    }

    _receivePort = ReceivePort();
    _receivePort.listen((message) {
      if (message is Uint8List) {
        _messages.add(message);
      } else if (message is TransferableTypedData) {
        _messages.add(message.materialize().asUint8List());
      }
    });
  }

  static DynamicLibrary _openNativeLibrary() {
    // Apple platforms (iOS + macOS desktop): the bridge is linked into the
    // app process by the serious_python_bridge pod and registered with CPython
    // via inittab. DynamicLibrary.process() resolves DartBridge_* via dlsym
    // on the host process; no separate dylib open is needed.
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    if (Platform.isWindows) return DynamicLibrary.open('flet_bridge.dll');
    if (Platform.isLinux || Platform.isAndroid) {
      return DynamicLibrary.open('libflet_bridge.so');
    }
    throw UnsupportedError(
        'serious_python_bridge does not support ${Platform.operatingSystem}');
  }

  /// Bytes posted from Python via `dart_bridge.send_bytes(port, payload)`.
  Stream<Uint8List> get messages => _messages.stream;

  /// Native port id to hand to Python so it can post back to this bridge.
  int get nativePort => _receivePort.sendPort.nativePort;

  /// Send a buffer to the Python handler registered via
  /// `dart_bridge.set_enqueue_handler_func`.
  ///
  /// The call is synchronous and acquires the Python GIL for the duration of
  /// the dispatch. Callers should run this off the root isolate to avoid
  /// stalling Flutter UI frames.
  void send(Uint8List bytes) {
    using((arena) {
      final ptr = arena<Uint8>(bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      _enqueueMessage(ptr, bytes.length);
    });
  }

  /// Release resources and tear down the singleton. After dispose, callers
  /// must invoke `PythonBridge.init()` again before further use.
  void dispose() {
    _receivePort.close();
    _messages.close();
    _instance = null;
  }
}
