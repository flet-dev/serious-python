# serious_python_bridge

A generic in-process Dart ↔ Python byte transport for the embedded Python
runtime provided by [`serious_python`](../serious_python). Eliminates the
socket/TCP/WebSocket overhead of out-of-process IPC by exchanging bytes
directly across the Dart FFI / CPython C API boundary.

This package is **independent of any specific protocol** — it exchanges
opaque byte buffers. Higher-level frameworks (e.g. Flet) layer their own
serialization (msgpack, JSON, etc.) on top.

## Usage

Dart side:

```dart
import 'package:serious_python_bridge/serious_python_bridge.dart';

final bridge = PythonBridge.init();

bridge.messages.listen((bytes) {
  // bytes posted by Python via dart_bridge.send_bytes(port, payload)
});

// Hand off the native port id to Python (typically as the first frame).
bridge.send(_encodeNativePort(bridge.nativePort));

// Send arbitrary bytes to Python.
bridge.send(Uint8List.fromList([0x01, 0x02, 0x03]));
```

Python side (executed inside the embedded interpreter started by
`serious_python`):

```python
import dart_bridge

def on_message(data: bytes) -> None:
    ...

dart_bridge.set_enqueue_handler_func(on_message)
dart_bridge.send_bytes(native_port, b"reply")
```

## Threading

`PythonBridge.send()` is synchronous and acquires the Python GIL for the
duration of the dispatch. Call it from a dedicated isolate rather than the
root isolate to avoid stalling Flutter UI frames.

## License

See [LICENSE](LICENSE).
