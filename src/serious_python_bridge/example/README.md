# serious_python_bridge_example

Minimal Flutter app exercising [`serious_python_bridge`](../). Sends bytes
from Dart to Python via `PythonBridge.send()`, and Python echoes them back
through `dart_bridge.send_bytes()`. No Flet, no msgpack, no protocol layer —
the smallest possible end-to-end demonstration of the byte transport.

## Build the Python app bundle

Before running, package the Python source into `app/app.zip`:

```sh
# From this directory:
dart run serious_python:main package app/src --platform Darwin \
  --python-version 3.14
```

Substitute `Darwin` with `Linux`, `Windows`, or `Android` for those targets.
On Linux/Windows/Android also pass `--bridge` so the prebuilt `dart_bridge`
Python shim is downloaded from the `serious-python` GitHub Release and
dropped into the bundled site-packages. (Not required on macOS/iOS — the
shim is statically linked into the app process and registered with CPython
via `serious_python_darwin`'s `registerPythonExtension` hook.)

## Run

```sh
flutter run -d macos    # or -d linux / windows / <device id>
```

The app starts the embedded Python interpreter (which runs `app/src/main.py`
in a background thread), sends an 8-byte handshake frame containing the Dart
`ReceivePort` native port id, and then sends `ping #N` payloads when the
button is pressed. Python echoes them back; received messages appear in the
list view.
