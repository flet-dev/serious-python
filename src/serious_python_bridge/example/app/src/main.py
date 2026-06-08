"""Echo loop exercising serious_python_bridge.

Protocol used by this example (NOT the Flet protocol — this is just the
simplest possible thing that proves the byte transport works):

* First frame from Dart: 8-byte little-endian int64 = the Dart native port id
  that Python should reply to. Captured into ``native_port`` and not echoed.
* Subsequent frames: arbitrary bytes; echoed back unchanged, prefixed with
  ``b"echo: "``.

Python keeps the interpreter alive indefinitely so messages can keep arriving;
Dart drives the lifetime (when the app exits, the embedded Python is torn down).
"""

from __future__ import annotations

import struct
import sys
import threading

import dart_bridge

native_port: int | None = None
_ready = threading.Event()


def on_dart_message(data: bytes) -> None:
    global native_port

    if native_port is None:
        if len(data) != 8:
            print(
                f"[bridge_example] expected 8-byte handshake, got {len(data)} bytes",
                file=sys.stderr,
                flush=True,
            )
            return
        native_port = struct.unpack("<q", data)[0]
        print(f"[bridge_example] handshake complete, native_port={native_port}", flush=True)
        _ready.set()
        return

    print(f"[bridge_example] received {data!r}", flush=True)
    dart_bridge.send_bytes(native_port, b"echo: " + data)


dart_bridge.set_enqueue_handler_func(on_dart_message)
print("[bridge_example] handler registered, awaiting messages", flush=True)

# Keep the embedded interpreter alive; Dart drives the process lifetime.
threading.Event().wait()
