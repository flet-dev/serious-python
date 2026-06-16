import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// FFI bindings for the `dart_bridge` C library published by
/// [flet-dev/dart-bridge](https://github.com/flet-dev/dart-bridge).
///
/// One binding lives in this platform-interface package so every
/// `serious_python_*` plugin can share it. The library handle resolution
/// differs by platform:
///
/// - Apple (macOS/iOS): statically linked into the host app via
///   `dart_bridge.xcframework` — looked up through [DynamicLibrary.process].
/// - Android: bundled as `libdart_bridge.so` in jniLibs — opened by name.
/// - Linux: bundled next to the executable — opened by name.
/// - Windows: bundled next to the .exe, with a separate Debug-CRT variant
///   `dart_bridge_d.dll` for `fvm flutter run`.
///
/// Mirrors the C surface declared in
/// [dart-bridge/src/dart_bridge.c](https://github.com/flet-dev/dart-bridge/blob/main/src/dart_bridge.c)
/// and [dart-bridge/src/serious_python_run.c](https://github.com/flet-dev/dart-bridge/blob/main/src/serious_python_run.c).

// ---------------------------------------------------------------------------
// C struct layout for serious_python_run
// ---------------------------------------------------------------------------

final class SpRunConfig extends Struct {
  @Int32()
  external int mode; // SP_RUN_PATH=0, SP_RUN_SCRIPT=1

  external Pointer<Utf8> appPath;
  external Pointer<Utf8> scriptSource;
  external Pointer<Utf8> programName;
  external Pointer<Pointer<Utf8>> modulePaths; // NULL-terminated
  external Pointer<Pointer<Utf8>> envKeys; // NULL-terminated
  external Pointer<Pointer<Utf8>> envValues; // parallel to envKeys

  @Int32()
  external int sync;

  @Int64()
  external int completionPort;
}

const int spRunPath = 0;
const int spRunScript = 1;

// ---------------------------------------------------------------------------
// Native + Dart function signatures
// ---------------------------------------------------------------------------

typedef _SeriousPythonRunNative = Int32 Function(Pointer<SpRunConfig>);
typedef _SeriousPythonRunDart = int Function(Pointer<SpRunConfig>);

typedef _DartBridgeInitDartApiDLNative = IntPtr Function(Pointer<Void>);
typedef _DartBridgeInitDartApiDLDart = int Function(Pointer<Void>);

typedef _DartBridgeEnqueueMessageNative = Int32 Function(
    Int64, Pointer<Uint8>, IntPtr);
typedef _DartBridgeEnqueueMessageDart = int Function(
    int, Pointer<Uint8>, int);

typedef _DartBridgeIsPythonInitializedNative = Int32 Function();
typedef _DartBridgeIsPythonInitializedDart = int Function();

typedef _DartBridgeSignalDartSessionNative = Void Function(
    Int32, Pointer<Pointer<Utf8>>, Pointer<Int64>);
typedef _DartBridgeSignalDartSessionDart = void Function(
    int, Pointer<Pointer<Utf8>>, Pointer<Int64>);

// ---------------------------------------------------------------------------
// Library binding
// ---------------------------------------------------------------------------

/// Loaded dart_bridge symbols. Use [DartBridge.instance] for the default
/// per-platform handle, or [DartBridge.open] / [DartBridge.process] to load
/// from a specific source (mostly useful for tests).
class DartBridge {
  DartBridge._(this._lib) {
    _run = _lib
        .lookup<NativeFunction<_SeriousPythonRunNative>>('serious_python_run')
        .asFunction<_SeriousPythonRunDart>();
    _initApiDL = _lib
        .lookup<NativeFunction<_DartBridgeInitDartApiDLNative>>(
            'DartBridge_InitDartApiDL')
        .asFunction<_DartBridgeInitDartApiDLDart>();
    _enqueueMessage = _lib
        .lookup<NativeFunction<_DartBridgeEnqueueMessageNative>>(
            'DartBridge_EnqueueMessage')
        .asFunction<_DartBridgeEnqueueMessageDart>();
    // dart_bridge >= 1.3.0 exports. Use lookupOrNull so older binaries
    // still load (calls into the wrappers below become safe no-ops);
    // makes the Dart/Python rollout decoupled from the libdart_bridge
    // release cadence.
    _isPythonInitialized = _lookupOrNull<_DartBridgeIsPythonInitializedNative,
        _DartBridgeIsPythonInitializedDart>(
      'dart_bridge_is_python_initialized',
      (f) => f.asFunction<_DartBridgeIsPythonInitializedDart>(),
    );
    _signalDartSession = _lookupOrNull<_DartBridgeSignalDartSessionNative,
        _DartBridgeSignalDartSessionDart>(
      'dart_bridge_signal_dart_session',
      (f) => f.asFunction<_DartBridgeSignalDartSessionDart>(),
    );
  }

  // Generic helper for soft symbol lookup — returns null if the binary
  // doesn't export the symbol (e.g. running against a pre-1.3.0
  // libdart_bridge).
  T? _lookupOrNull<N extends Function, T extends Function>(
      String name, T Function(Pointer<NativeFunction<N>>) bind) {
    try {
      final ptr = _lib.lookup<NativeFunction<N>>(name);
      return bind(ptr);
    } on ArgumentError {
      return null;
    }
  }

  final DynamicLibrary _lib;
  late final _SeriousPythonRunDart _run;
  late final _DartBridgeInitDartApiDLDart _initApiDL;
  late final _DartBridgeEnqueueMessageDart _enqueueMessage;
  late final _DartBridgeIsPythonInitializedDart? _isPythonInitialized;
  late final _DartBridgeSignalDartSessionDart? _signalDartSession;

  static DartBridge? _instance;

  /// Default per-platform loader. Cached after the first call.
  static DartBridge get instance => _instance ??= DartBridge._(_loadDefault());

  /// Test/override entry point: open a specific library path. Replaces the
  /// cached instance.
  static DartBridge open(String path) =>
      _instance = DartBridge._(DynamicLibrary.open(path));

  /// Test/override entry point: resolve from the host process (Apple).
  /// Replaces the cached instance.
  static DartBridge process() =>
      _instance = DartBridge._(DynamicLibrary.process());

  static DynamicLibrary _loadDefault() {
    if (Platform.isMacOS || Platform.isIOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libdart_bridge.so');
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open(
          kDebugMode ? 'dart_bridge_d.dll' : 'dart_bridge.dll');
    }
    throw UnsupportedError(
        'serious_python: dart_bridge has no binary for this platform');
  }

  /// Initialize the Dart Native API DL hooks so the worker thread spawned by
  /// `serious_python_run` and `send_bytes` (Python→Dart) can post to ports.
  /// Idempotent — calling more than once is a cheap no-op past the first.
  bool _apiDLInitialized = false;
  void initDartApiDL() {
    if (_apiDLInitialized) return;
    final rc = _initApiDL(NativeApi.initializeApiDLData);
    if (rc != 0) {
      throw StateError('DartBridge_InitDartApiDL failed with code $rc');
    }
    _apiDLInitialized = true;
  }

  /// Run a Python program (`appPath` mode) or source string (`script` mode).
  /// See [SpRunConfig] / `serious_python_run`.
  int run(Pointer<SpRunConfig> cfg) => _run(cfg);

  /// Deliver bytes to the Python handler registered for [port]. Returns 0 on
  /// successful delivery, -1 if no handler is registered (caller may retry),
  /// or -2 if the interpreter is not initialized.
  int enqueueMessage(int port, Pointer<Uint8> data, int len) =>
      _enqueueMessage(port, data, len);

  /// True if libdart_bridge has already brought up an embedded CPython.
  /// On Android process reuse (OS keeps the process alive across a Dart
  /// VM restart), this returns true on the second Dart VM's PythonBridge
  /// construction.
  ///
  /// Returns false when running against a pre-1.3.0 libdart_bridge that
  /// doesn't export the underlying C function — callers should treat that
  /// as "fresh start path", which is the correct behaviour on every
  /// platform that hasn't seen this binary update yet.
  bool get isPythonInitialized {
    final f = _isPythonInitialized;
    if (f == null) return false;
    return f() != 0;
  }

  /// Signal the running Python program that a new Dart VM session is
  /// active. On a fresh start where Python isn't loaded yet, this is a
  /// cheap no-op inside libdart_bridge. On Android process reuse it fires
  /// every Python callback registered via
  /// `dart_bridge.add_session_restart_handler(...)`, carrying the new
  /// native port numbers as a `{label: port}` map.
  ///
  /// [portMap] keys are arbitrary labels — current callers use
  /// `"protocol"` and `"exit"` to match flet's build template wiring.
  ///
  /// No-op when running against a pre-1.3.0 libdart_bridge.
  void signalDartSession(Map<String, int> portMap) {
    final f = _signalDartSession;
    if (f == null || portMap.isEmpty) return;
    using((Arena arena) {
      final labels = arena<Pointer<Utf8>>(portMap.length);
      final ports = arena<Int64>(portMap.length);
      var i = 0;
      for (final entry in portMap.entries) {
        labels[i] = entry.key.toNativeUtf8(allocator: arena);
        ports[i] = entry.value;
        i++;
      }
      f(portMap.length, labels, ports);
    });
  }
}

// ---------------------------------------------------------------------------
// High-level helper: build SpRunConfig, run, free.
// ---------------------------------------------------------------------------

/// Allocates a NULL-terminated `char**` for a list of strings using [arena].
Pointer<Pointer<Utf8>>? _toCStringArray(Arena arena, List<String>? strings) {
  if (strings == null) return null;
  final ptr = arena<Pointer<Utf8>>(strings.length + 1);
  for (var i = 0; i < strings.length; i++) {
    ptr[i] = strings[i].toNativeUtf8(allocator: arena);
  }
  ptr[strings.length] = nullptr;
  return ptr;
}

/// Run a Python program via dart_bridge.
///
/// - `sync: false` (default): spawn a worker thread and return immediately
///   with 0 on successful spawn. The Python run continues in the background;
///   bridge traffic flows over Dart ↔ Python ports independently.
/// - `sync: true`: block the calling thread inside the Python interpreter
///   until the program finishes, then return its exit code.
///
/// If [completionPort] is provided, the exit code is also posted to that
/// Dart port via `Dart_PostInteger_DL` when Python finishes. Default `0`
/// disables the post.
int runPython({
  required DartBridge bridge,
  String? appPath,
  String? script,
  String? programName,
  List<String>? modulePaths,
  Map<String, String>? environmentVariables,
  bool sync = false,
  int completionPort = 0,
}) {
  if ((appPath == null) == (script == null)) {
    throw ArgumentError(
        'Provide exactly one of appPath / script (got both or neither)');
  }

  // Worker thread needs the Dart Native API DL hooks so it can post to a
  // completion port. Idempotent past the first call; cheap to do every time.
  bridge.initDartApiDL();

  return using((Arena arena) {
    final cfg = arena<SpRunConfig>();
    cfg.ref
      ..mode = script != null ? spRunScript : spRunPath
      ..appPath =
          appPath != null ? appPath.toNativeUtf8(allocator: arena) : nullptr
      ..scriptSource =
          script != null ? script.toNativeUtf8(allocator: arena) : nullptr
      ..programName = programName != null
          ? programName.toNativeUtf8(allocator: arena)
          : nullptr
      ..modulePaths = _toCStringArray(arena, modulePaths) ?? nullptr
      ..sync = sync ? 1 : 0
      ..completionPort = completionPort;

    if (environmentVariables != null && environmentVariables.isNotEmpty) {
      final keys = environmentVariables.keys.toList();
      final values = keys.map((k) => environmentVariables[k]!).toList();
      cfg.ref.envKeys = _toCStringArray(arena, keys)!;
      cfg.ref.envValues = _toCStringArray(arena, values)!;
    } else {
      cfg.ref.envKeys = nullptr;
      cfg.ref.envValues = nullptr;
    }

    return bridge.run(cfg);
  });
}
