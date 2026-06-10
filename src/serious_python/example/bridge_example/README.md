# bridge_example

Minimal Flutter app exercising [`PythonBridge`](../../lib/bridge.dart) —
the in-process byte transport between Dart and the embedded CPython
runtime. Sends bytes from Dart to Python via `bridge.send()`, and Python
echoes them back through `dart_bridge.send_bytes()`. No Flet, no msgpack,
no protocol layer — the smallest possible end-to-end demonstration of the
transport.

## Build the Python app bundle

Before running, package the Python source into `app/app.zip`:

```sh
# From this directory:
dart run serious_python:main package app/src --platform Darwin \
  --python-version 3.14
```

Substitute `Darwin` with `Linux`, `Windows`, or `Android` for those
targets (each platform plugin's CMake/Gradle pipeline downloads the
prebuilt `dart_bridge` native binary from
[flet-dev/dart-bridge](https://github.com/flet-dev/dart-bridge) at build
time — no `--bridge` flag, no PyPI wheel).

## Run

```sh
flutter run -d macos    # or -d linux / windows / <device id>
```

How it works:

1. Dart creates a `PythonBridge`; its `port` (a `ReceivePort.sendPort.nativePort`)
   is exported to Python via the `BRIDGE_EXAMPLE_PORT` env var passed to
   `SeriousPython.run()`.
2. Python reads the env var, registers a handler keyed on that port via
   `dart_bridge.set_enqueue_handler_func(port, handler)`, and echoes any
   incoming frame with a `b"echo: "` prefix using `dart_bridge.send_bytes(port, ...)`.
3. Dart's `bridge.send()` returns `false` until the Python-side handler
   is registered; the example retries briefly to cover that startup race.
