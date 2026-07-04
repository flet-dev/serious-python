# Dedicated data channels for Flet widgets

> **Status:** implemented in Flet 0.86.0.
> Implementation lives in
> [`packages/flet/lib/src/transport/data_channel.dart`](https://github.com/flet-dev/flet/blob/main/packages/flet/lib/src/transport/data_channel.dart)
> (Dart abstract API),
> [`packages/flet/lib/src/transport/protocol_muxed_data_channel.dart`](https://github.com/flet-dev/flet/blob/main/packages/flet/lib/src/transport/protocol_muxed_data_channel.dart)
> (cross-mode muxed fallback), and
> [`sdk/python/packages/flet/src/flet/data_channel.py`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet/src/flet/data_channel.py)
> (Python). First production consumer is
> [`flet-charts.MatplotlibChartCanvas`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet-charts/src/flet_charts/matplotlib_chart_canvas.py).
> Empirical baseline: this repo's
> [`bridge_example`](../src/serious_python/example/bridge_example/README.md).

## Problem

Flet's main control protocol carries widget state and events over a single
MsgPack-framed channel. Every byte — including bulk payloads like image
frames or audio buffers — pays the protocol cost:

- Python: `msgpack.packb(big_bytes_field)` allocates a fresh buffer and
  serializes into it.
- Dart: the streaming MsgPack decoder allocates another `Uint8List`,
  decodes the ext, copies again.

End-to-end throughput tops out around ~1 GB/s with several allocations
per frame. Fine for widget state diffs (tens of bytes per event). Not
fine for:

- A chart / image widget receiving large bitmaps from Python (1080p RGBA
  at 60 fps = 480 MB/s).
- A camera widget pushing frames from Dart into Python for ML inference.
- A microphone widget streaming PCM to a Python signal-processing
  pipeline.

`DataChannel` gives such widgets a dedicated byte channel alongside the
protocol — control flows still ride the protocol, bulk bytes bypass
MsgPack entirely.

## What's available today

`libdart_bridge` already supports an arbitrary number of independent
port↔handler pairs per process. The `flet build` template uses two
`PythonBridge` instances internally (one for the Flet protocol, one for
exit-code transmission). [`bridge_example`](../src/serious_python/example/bridge_example/)
opens two channels (JSON control + raw bytes echo) and round-trips
~16 MB payloads at **7 GiB/s** on M2 Pro — see
[bridge_example/README.md → Performance & memory baseline](../src/serious_python/example/bridge_example/README.md#performance--memory-baseline).

A widget gets the same headroom: open a dedicated channel via `flet`'s
`DataChannel` API, ship raw bytes, never touch MsgPack on the hot path.

## Architecture

```
              package:flet  (no Python deps, no transport deps)
   ┌──────────────────────────────────────────────────────────────────┐
   │ abstract DataChannel { id, messages, send, close }               │
   │ abstract DataChannelFactory { open() }                           │
   │ FletApp(dataChannelFactory: …)                                   │
   │ FletBackend.openDataChannel()                                    │
   │                                                                  │
   │ DEFAULT (built-in) ProtocolMuxedDataChannelFactory:              │
   │   – muxes bytes over the existing FletBackendChannel             │
   │   – works on every transport (UDS, TCP, WebSocket, postMessage)  │
   │   – activated when no faster factory was injected                │
   └──────────────────────────────────────────────────────────────────┘
                  ▲                                          ▲
                  │ injected by                              │ used by every non-embedded mode:
                  │ flet build template                      │   - dev (UDS/TCP socket)
                  │                                          │   - web with Pyodide (postMessage + Transferable)
                  │                                          │   - web with Python server (WebSocket)
   ┌──────────────────────────────┐         ┌──────────────────────────────────────────────────────┐
   │ _PythonBridgeDataChannel     │         │ DEFAULT (built-in) ProtocolMuxedDataChannel impl     │
   │ wraps PythonBridge directly  │         │ rides the active FletBackendChannel using the wire   │
   │ (4–7 GiB/s)                  │         │ format below. Zero-copy on postMessage via           │
   └──────────────────────────────┘         │ Transferable ArrayBuffer on that transport.          │
                                            └──────────────────────────────────────────────────────┘
                  ▲ uses
   ┌─────────────────────────────────────────────────────────────────┐
   │ Extension widget (3rd-party) — imports only `package:flet`      │
   │ Dart:    final ch = FletBackend.of(context).openDataChannel();  │
   │          ch.send(bytes); ch.messages.listen(...)                │
   │ Python:  on_data_channel_open handler ↓                         │
   │          self._channel = self.get_data_channel(e.channel_id)    │
   └─────────────────────────────────────────────────────────────────┘
```

Key shape decisions that fell out of implementation:

1. **`flet` stays Python-independent.** Widget code on either side imports
   only `package:flet` / `flet`. The `serious_python` dependency lives in
   the `flet build` template's `native_runtime.dart`, behind a conditional
   import. Web builds don't pull it in at all.
2. **Allocator: Dart side, always.** `FletBackend.of(context).openDataChannel()`
   mints the id (a Dart native port in embedded mode, a monotonic u32 in
   muxed mode). Python never allocates a channel — it only attaches to
   ones Dart has already opened.
3. **Handshake: control event, not a property.** When the Dart widget
   opens a channel it fires `data_channel_open` (a normal Flet control
   event) carrying `{channel_name, channel_id}`. Python receives this via
   the standard event handler and calls `self.get_data_channel(channel_id)`
   to attach. No polling, no exception, no race window. A widget that
   opens N channels fires N events with distinct `channel_name` values
   for handler-side dispatch.
4. **Cross-mode.** Same widget code runs in four modes; only the
   transport changes (see *Cross-mode operation* below).

## Public API

### Python side

```python
import flet as ft
from typing import Optional

@ft.control("MyImageChart")
class MyImageChart(ft.LayoutControl):
    on_data_channel_open: Optional[
        ft.EventHandler[ft.DataChannelOpenEvent]
    ] = None

    def init(self) -> None:
        self._frames: Optional[ft.DataChannel] = None
        if self.on_data_channel_open is None:
            self.on_data_channel_open = self._capture_channel

    def _capture_channel(self, e: ft.DataChannelOpenEvent) -> None:
        # Single-channel widget — no need to dispatch on e.channel_name.
        # Multi-channel widgets `match e.channel_name:` here.
        self._frames = self.get_data_channel(e.channel_id)
        # Optional inbound handler:
        self._frames.on_bytes(self._on_frame_from_dart)

    def push_frame(self, rgba_bytes: bytes) -> None:
        if self._frames is not None:
            self._frames.send(rgba_bytes)

    def _on_frame_from_dart(self, payload: bytes) -> None:
        # called from the transport's delivery thread — push to a queue,
        # don't block here
        ...
```

### Dart side

```dart
import 'package:flet/flet.dart';
// No imports of `serious_python` or `dart_bridge`.

class MyImageChartState extends State<MyImageChartWidget> {
  late final DataChannel _frames;
  StreamSubscription<Uint8List>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_frames != null) return;  // initialize lazily, once
    _frames = FletBackend.of(context).openDataChannel();
    _sub = _frames.messages.listen(_onFrameFromPython);
    // Announce the channel to Python.
    widget.control.triggerEvent("data_channel_open", {
      "channel_name": "frames",
      "channel_id": _frames.id,
    });
  }

  void _onFrameFromPython(Uint8List bytes) {
    // Hand to a Texture, dart:ui.Image.fromPixels, etc.
  }

  @override
  void dispose() {
    _sub?.cancel();
    _frames.close();
    super.dispose();
  }
}
```

The `data_channel_open` event name is a **Flet convention, not framework-
intercepted** — the framework provides `Control.get_data_channel(id)` and
`FletBackend.openDataChannel()`; the widget wires the event on both ends.

## Cross-mode operation

Flet runs Python in different processes depending on deployment. Each
mode picks its own data-channel transport; the widget API is identical:

| Mode | Flet protocol transport | DataChannel transport | Performance |
|------|------------------------|----------------------|-------------|
| **Embedded native** (`flet build` apk/macos/ios/...) | dart_bridge FFI | Dedicated `PythonBridge` per channel | 4–7 GiB/s (memory-copy bound) |
| **Web with Pyodide** | `postMessage` | Muxed over postMessage, Transferable ArrayBuffer | ~memory-bandwidth, zero-copy |
| **`flet run` dev mode** | UDS / TCP socket | Muxed over the protocol socket | ~hundreds of MB/s |
| **Web with Python server** | WebSocket | Muxed over WebSocket | ~hundreds of MB/s |

Embedded native gets dedicated bridges because the FFI runtime supports
them natively at zero overhead. The other three modes share the built-in
`ProtocolMuxedDataChannelFactory` — channel frames ride the same byte
transport as the Flet protocol, with a 1-byte type discriminator to
disambiguate.

## Wire format (muxed fallback)

```
type 0x00  →  legacy Flet protocol frame (msgpack array [ClientAction, body])
type 0x01  →  raw DataChannel frame: [channel_id:u32 LE][raw payload bytes]
```

- **Message-oriented transports** (WebSocket, postMessage, dart_bridge):
  each `send` is one packet of shape `[type:u8][payload]`. 5 bytes of
  overhead per data-channel frame.
- **Stream-oriented transports** (UDS, TCP): each packet is prefixed
  with `[length:u32 LE]` so the receiver can re-frame. 9 bytes of
  overhead per data-channel frame.

Under 1% overhead at any payload size that motivates a dedicated channel
(≥ 1 KB).

**Channel-id allocation.** Embedded mode uses the Dart native port (64-bit,
allocated by `RawReceivePort`). Muxed mode uses a session-scoped
monotonic 32-bit counter — 0 reserved as "unallocated," ids never recycled
within a session. At 1 alloc/μs the u32 space lasts ~1 hour; real apps
open single-digit channels. The public `DataChannel.id : int` API is
64-bit; the u32 truncation is an internal contract of the muxed wire
format only.

**Compatibility.** This wire format is **not backwards-compatible** with
pre-0.86 Flet servers/clients. Mixed-version `flet run` setups fail at
the first packet decode. See the Flet 0.86 breaking-change guide:
[Flet protocol framing upgraded for DataChannel support](https://flet.dev/docs/updates/breaking-changes/data-channel-protocol-upgrade).

## Backpressure pattern (WebAgg-style)

`DataChannel.send` is **synchronous fire-and-forget** on the Python side.
For producers that can outpace the consumer (camera streams, animation
loops, interactive matplotlib drags), the widget must implement explicit
backpressure — otherwise frames pile up in the Dart-side queue and replay
in a burst.

The canonical pattern is a 1-byte ack from Dart after each frame paints,
mirroring matplotlib WebAgg's `img.onload` → `waiting=false` flow:

**Dart side**, after the apply chain resolves:
```dart
_enqueue(() => applyFull(payload)).whenComplete(() {
  _channel?.send(Uint8List.fromList([0xFF]));   // ack
});
```

**Python side** registers a callback for inbound bytes that observes the
ack and clears the producer-side `_waiting` flag. Matplotlib's existing
draw-request gate (`if not self._waiting: send(draw_request)`) then
naturally rate-limits to one frame in flight.

Reference: [`flet-charts/matplotlib_chart_canvas`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet-charts/src/flet_charts/matplotlib_chart_canvas.py)
+ [`matplotlib_chart_canvas.dart`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet-charts/src/flutter/flet_charts/lib/src/matplotlib_chart_canvas.dart).
The Python side exposes `canvas.set_on_frame_applied(callback)` for
producer widgets like `MatplotlibChart` to chain onto.

## Concurrency model

### Python side — GIL-bound

`channel.on_bytes(handler)` fires the handler synchronously under the GIL
on whatever OS thread the transport delivered from (dart_bridge thread in
embedded mode, asyncio loop in muxed mode). Heavy work in the handler
starves Python; the right pattern is enqueue-then-process with a bounded
queue + worker pool:

```python
def did_mount(self):
    self._queue = queue.Queue(maxsize=4)         # bounded → drop policy
    self._pool = ThreadPoolExecutor(max_workers=4)
    self._frames.on_bytes(self._enqueue)
    threading.Thread(target=self._pump, daemon=True).start()

def _enqueue(self, payload):
    try: self._queue.put_nowait(payload)
    except queue.Full: pass                       # drop overflow

def _pump(self):
    while True:
        payload = self._queue.get()
        self._pool.submit(self._decode_and_reply, payload)
```

Real parallelism comes from C extensions that **release the GIL during
their work** — NumPy, PyTorch, Pillow, cryptography. Pure-Python CPU work
serialises on the GIL; for that, use `multiprocessing` or
PEP 684 subinterpreters. Caveat: `multiprocessing` works in the embedded
runtime only on **desktop** hosts whose binary services the spawn re-exec
protocol via `serious_python_main` (dart_bridge >= 1.5.0, flet >= 0.86 build
template); it is not available on iOS/Android, where the OS forbids spawning
child processes.

### Dart side — Isolate scope

**`FletBackend.of(context).openDataChannel()` is main-Isolate only.**
`BuildContext` is part of Flutter's widget tree, which lives on the main
Isolate. The `PythonBridge` it constructs has its `RawReceivePort` on the
main Isolate.

For worker-Isolate parallelism (e.g. a video decoder offloading texture
upload from the UI thread), the worker has to construct its **own**
`PythonBridge` directly — bypassing the framework helper, importing
`package:serious_python/bridge.dart` in the worker's entry-point file —
and ship its port back to main via `SendPort` for the
`data_channel_open` event fire.

| Operation | Safe? |
|-----------|-------|
| `FletBackend.of(context).openDataChannel()` from a worker Isolate | ✗ BuildContext is main-Isolate only |
| Multiple `PythonBridge` instances across Isolates (worker constructs its own) | ✓ libdart_bridge multiplexes |
| One `PythonBridge` instance used from multiple Isolates | ✗ `RawReceivePort` is single-Isolate |
| Python `dart_bridge.send_bytes(port, ...)` from worker threads | ✓ serialised internally |
| Python handler running concurrently for one port | ✗ GIL — one in-flight handler per port |

Non-embedded modes are single-Isolate by design — the muxed channel
registry lives in `FletBackend` on the main Isolate. Workers there ship
payloads via `TransferableTypedData` from/to main rather than opening
channels themselves.

## Empirical baseline

Measured 2026-06-12 on M2 Pro / macOS 26.5 / Flutter Debug build via
[`bridge_example`](../src/serious_python/example/bridge_example/README.md).
These are the `PythonBridge` numbers — they apply directly to embedded
native mode. Muxed-fallback throughput on dev/web transports is
transport-bound (sockets ~hundreds of MB/s; postMessage Transferable
~memory-bandwidth at large payloads).

| Payload | Mean round-trip | Throughput |
|--------:|----------------:|-----------:|
|    1 KB |     0.08 ms     |     23 MB/s |
|   64 KB |     0.09 ms     |    1.3 GB/s |
|    1 MB |     0.45 ms     |  **4.5 GB/s** |
|   16 MB |     4.45 ms     |  **7.2 GB/s** |

Memory: 1000 × 1 MB hammer loop (2 GB through the bridge) grows Python's
`tracemalloc` heap by **0 bytes**. Peak in-flight is one frame's worth.

For a real-widget reference, the matplotlib pilot at a 3D figure with
heavy surface + contour layers measures ~15 fps at ~200 KB PNG/frame;
the bottleneck is matplotlib's mplot3d render (~53 ms/frame), not the
DataChannel (which runs at ~3 MB/s here against a ~4500 MB/s budget).

## Known limitations / not in this release

- **No built-in backpressure knob.** Per-channel queue depth or
  "latest frame only" mode is the widget author's responsibility (see
  *Backpressure pattern* above). A framework-level
  `channel.queue_depth` knob is a future addition.
- **No discovery / introspection.** No "how many channels are open" or
  "queue depth per channel" debug surface yet.
- **No Pyodide-dedicated MessageChannels.** v1 muxes through one
  `postMessage` transport with Transferable for zero-copy outbound. If
  head-of-line blocking on Pyodide becomes a visible issue, a v2 PR can
  inject a per-channel `MessageChannel` factory through the same
  `DataChannelFactory` injection point — no widget API changes.
- **No Python-initiated channel opens.** Dart is the always-allocator.
  Reversing direction (Python wants a channel before any Dart widget has
  asked) is a v2 question.
- **True zero-copy shared memory** (mmap + offset handoff) — the bridge
  still does one `memcpy` per direction. Eliminating it requires
  lifetime/ownership coordination between Dart's GC and CPython's
  refcounting that's out of scope here. The 4–7 GiB/s ceiling is plenty
  for the foreseeable use cases.

## References

- [`bridge_example`](../src/serious_python/example/bridge_example/) —
  empirical baseline + reproducible test suite. Throughput and memory
  numbers above come from its `throughput_test.dart` and `memory_test.dart`.
- [Flet 0.86 breaking-change guide](https://flet.dev/docs/updates/breaking-changes/data-channel-protocol-upgrade)
  — wire format change details for anyone speaking the Flet protocol
  outside the bundled CLI/runtime.
- [`matplotlib_chart_canvas.py`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet-charts/src/flet_charts/matplotlib_chart_canvas.py)
  + [`matplotlib_chart_canvas.dart`](https://github.com/flet-dev/flet/blob/main/sdk/python/packages/flet-charts/src/flutter/flet_charts/lib/src/matplotlib_chart_canvas.dart)
  — first production widget using DataChannel end-to-end, with backpressure ack.
