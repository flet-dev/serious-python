"""Two-channel PythonBridge harness for bridge_example.

Channels (matching dart_bridge v1.2+ keyed-handler API; each
PythonBridge instance has its own native port):

  - **control** (BRIDGE_EXAMPLE_CONTROL_PORT): UTF-8 JSON frames. Dart
    sends `{"op": ...}`; Python responds with `{"event": ...}`. Used
    by the interactivity test (counter + version) and the memory test
    (rss + tracemalloc snapshots).
  - **echo** (BRIDGE_EXAMPLE_ECHO_PORT): pure raw bytes. Python echoes
    whatever it receives, verbatim. Used by the throughput test and
    by the memory test's hammer loop — keeping the per-frame cost on
    Python's side as close to zero as possible so any cost we measure
    is the transport's.

Python keeps the interpreter alive indefinitely so messages can keep
arriving; Dart drives the process lifetime.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import tracemalloc

import dart_bridge

CONTROL_PORT_ENV = "BRIDGE_EXAMPLE_CONTROL_PORT"
ECHO_PORT_ENV = "BRIDGE_EXAMPLE_ECHO_PORT"

try:
    control_port = int(os.environ[CONTROL_PORT_ENV])
    echo_port = int(os.environ[ECHO_PORT_ENV])
except (KeyError, ValueError) as e:
    print(f"[bridge_example] missing/invalid env var: {e}",
          file=sys.stderr, flush=True)
    raise SystemExit(1)

counter = 0


def _rss_bytes() -> int:
    """Resident set size, in bytes.

    POSIX: ``resource.getrusage(RUSAGE_SELF).ru_maxrss``. macOS reports
    bytes; Linux/Android report kilobytes. We leave that unit quirk to
    the Dart caller — the leak assertion relies on ``tracemalloc``'s
    unit-stable bytes count, not on this number.

    Windows: ``resource`` isn't available — fall back to ctypes →
    GetProcessMemoryInfo.WorkingSetSize.
    """
    try:
        import resource
        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    except (ImportError, AttributeError):
        import ctypes
        from ctypes import wintypes

        class _PMC(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        psapi = ctypes.WinDLL("psapi")
        proc = ctypes.windll.kernel32.GetCurrentProcess()
        pmc = _PMC()
        pmc.cb = ctypes.sizeof(_PMC)
        psapi.GetProcessMemoryInfo(proc, ctypes.byref(pmc), pmc.cb)
        return pmc.WorkingSetSize


def _emit(event: dict) -> None:
    dart_bridge.send_bytes(control_port, json.dumps(event).encode("utf-8"))


def on_control(payload: bytes) -> None:
    global counter
    if not payload:
        return
    try:
        msg = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        # Forward-compatible: unknown / unparseable frames are dropped
        # silently rather than crashing the interpreter.
        return
    op = msg.get("op")
    if op == "inc":
        counter += 1
        _emit({"event": "count", "value": counter})
    elif op == "dec":
        counter -= 1
        _emit({"event": "count", "value": counter})
    elif op == "version":
        v = sys.version_info
        _emit({"event": "version", "value": f"{v.major}.{v.minor}.{v.micro}"})
    elif op == "mem":
        # tracemalloc adds ~10–20% overhead so we don't enable it until the
        # memory test asks for it — keeps the throughput test pristine.
        if not tracemalloc.is_tracing():
            tracemalloc.start()
        cur, peak = tracemalloc.get_traced_memory()
        _emit({
            "event": "mem",
            "rss": _rss_bytes(),
            "traced_current": cur,
            "traced_peak": peak,
        })


def on_echo(payload: bytes) -> None:
    # Verbatim, zero framing. The Dart-side Stopwatch around send →
    # bridge.messages.first wraps exactly the bridge transport.
    dart_bridge.send_bytes(echo_port, payload)


dart_bridge.set_enqueue_handler_func(control_port, on_control)
dart_bridge.set_enqueue_handler_func(echo_port, on_echo)
print(
    f"[bridge_example] control_port={control_port} echo_port={echo_port}",
    flush=True,
)

# Keep the embedded interpreter alive; Dart drives the process lifetime.
threading.Event().wait()
