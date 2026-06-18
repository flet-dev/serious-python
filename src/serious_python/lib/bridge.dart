/// In-process Dart ↔ Python byte channel.
///
/// See [PythonBridge] for the per-channel API. The lower-level [DartBridge]
/// singleton (from the platform-interface package) is re-exported here for
/// embedders that need the process-reuse / session-restart hooks added in
/// libdart_bridge 1.3.0 — `isPythonInitialized` and `signalDartSession`.
library;

export 'package:serious_python_platform_interface/src/dart_bridge_ffi.dart'
    show DartBridge;
export 'src/python_bridge.dart' show PythonBridge;
