"""Echo loop exercising PythonBridge (dart_bridge v1.2.0 keyed-handlers API).

Protocol:
    Dart side creates a PythonBridge; its native port is handed to Python via
    the BRIDGE_EXAMPLE_PORT env var. Python registers a handler for that port
    and echoes each received frame back prefixed with b"echo: ".

Python keeps the interpreter alive indefinitely so messages can keep arriving;
Dart drives the process lifetime (when the app exits, the embedded Python is
torn down).
"""

from __future__ import annotations

import os
import sys
import threading

import dart_bridge

PORT_ENV = "BRIDGE_EXAMPLE_PORT"

try:
    bridge_port = int(os.environ[PORT_ENV])
except (KeyError, ValueError) as e:
    print(f"[bridge_example] missing/invalid {PORT_ENV}: {e}",
          file=sys.stderr, flush=True)
    raise SystemExit(1)


def on_dart_message(data: bytes) -> None:
    print(f"[bridge_example] received {len(data)} bytes", flush=True)
    dart_bridge.send_bytes(bridge_port, b"echo: " + data)


dart_bridge.set_enqueue_handler_func(bridge_port, on_dart_message)
print(f"[bridge_example] handler registered on port {bridge_port}", flush=True)

# Keep the embedded interpreter alive; Dart drives the process lifetime.
threading.Event().wait()
