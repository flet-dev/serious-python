# bridge_example

Direct exercise of [`PythonBridge`](../../lib/bridge.dart) — the in-process byte transport between Dart and the embedded CPython runtime. No Flet, no MsgPack, no protocol layer beyond what this example draws itself. Used as the CI gate for the `serious_python` repo and as the perf / leak baseline for every change to `libdart_bridge`.

## What it does

Two independent `PythonBridge` channels open at startup; Python registers a handler per channel:

| Channel | Env var carrying the Dart-side native port to Python | Wire format                                  | Purpose                                  |
|---------|------------------------------------------------------|----------------------------------------------|------------------------------------------|
| Control | `BRIDGE_EXAMPLE_CONTROL_PORT`                        | UTF-8 JSON, `{"op": …}` ↔ `{"event": …}`     | Interactivity (counter, version), memory snapshots |
| Echo    | `BRIDGE_EXAMPLE_ECHO_PORT`                           | Raw bytes — Python echoes the frame verbatim | Throughput timing, memory hammer loop    |

Separating channels means the throughput / memory hot path is just `bridge.send` → `dart_bridge.send_bytes` echo back, with zero framing tax on either side. The JSON dispatcher only runs for tiny control messages where the encoding cost is irrelevant.

## Build the Python app bundle

```sh
# From this directory:
export SERIOUS_PYTHON_VERSION=3.14   # read by BOTH the package step and `flutter build`
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src --platform Darwin
```

Set `SERIOUS_PYTHON_VERSION` as an **environment variable** (not the `--python-version`
flag): the native build also reads it at `flutter run`/`flutter build` time, so a single
`export` keeps the bundled runtime and the installed packages on the same Python version.
`SERIOUS_PYTHON_APP` is where the processed app is staged for the platform build to
bundle (native targets ship the app unpacked next to the stdlib/site-packages — Android
ships it as a stored asset). Substitute `Darwin` with `Linux`, `Windows`, `iOS`, or `Android`. Each platform plugin's CMake / Gradle pipeline downloads the prebuilt `dart_bridge` native binary from [flet-dev/dart-bridge](https://github.com/flet-dev/dart-bridge) at build time — no `--bridge` flag, no PyPI wheel.

## Run

```sh
flutter run -d macos    # or -d linux / windows / <device id>
```

Tap `+` / `−` to send `{"op": "inc"}` / `{"op": "dec"}` on the control channel; the displayed counter updates from the Python-side `{"event": "count", "value": …}` response. The version banner is populated by an analogous `{"op": "version"}` round-trip on `initState`.

## Integration tests

Three tests under [`integration_test/`](integration_test/):

| Test                       | What it covers                                                                                       |
|----------------------------|------------------------------------------------------------------------------------------------------|
| `interactivity_test.dart`  | Counter +/-, version banner. Asserts UI text via Flutter widget keys; matches `EXPECTED_PYTHON_VERSION` if supplied via `--dart-define`. |
| `throughput_test.dart`     | Size sweep 1 KB → 16 MB, 100 round-trips each. Logs min/p50/p95/mean + MB/s. Floor assertion at ≥ 1 MB. |
| `memory_test.dart`         | 1 000 × 1 MB echo round-trips (~2 GB total). Snapshots Python `tracemalloc` + RSS before/after. Asserts `traced_delta < 5 MB`. |

```sh
# After `dart run serious_python:main package …`:
flutter test integration_test/throughput_test.dart -d macos
flutter test integration_test/memory_test.dart -d macos
flutter test integration_test/interactivity_test.dart -d macos \
  --dart-define=EXPECTED_PYTHON_VERSION=3.14
```

---

# Performance & memory baseline

> Measured 2026-06-12 on the bridge_example integration tests. Re-running these is the canonical way to refresh the numbers after any `libdart_bridge` / `serious-python` bump.

## Test environment

|                |                                                          |
|----------------|----------------------------------------------------------|
| Hardware       | MacBook Pro M2 Pro, 32 GB                                |
| OS             | macOS 26.5                                               |
| Python         | CPython 3.14.6 (embedded via `libdart_bridge`)           |
| Flutter        | 3.44.2, Debug build                                      |
| Test harness   | `bridge_example/integration_test/` (`flutter test integration_test`) |

## Throughput

Methodology — round-trip = `Dart.send(N bytes) → Python echo handler → Dart receives N bytes back`. Throughput counted as `(2 × N) / mean_seconds` since both directions cross the bridge. Payload is `Random()`-seeded so each iteration is unique. 100 iterations per size.

| Payload | min     | p50     | p95     | mean    | Throughput     |
|--------:|--------:|--------:|--------:|--------:|---------------:|
|    1 KB |  0.08 ms |  0.08 ms |  0.11 ms |  0.08 ms |        23 MB/s |
|   64 KB |  0.07 ms |  0.09 ms |  0.12 ms |  0.09 ms |     1.3 GB/s   |
|  256 KB |  0.11 ms |  0.16 ms |  0.33 ms |  0.21 ms |     2.4 GB/s   |
|    1 MB |  0.24 ms |  0.31 ms |  0.84 ms |  0.45 ms |   **4.5 GB/s** |
|    4 MB |  0.82 ms |  1.01 ms |  3.83 ms |  1.55 ms |     5.2 GB/s   |
|   16 MB |  2.45 ms |  3.32 ms |  9.12 ms |  4.45 ms |   **7.2 GB/s** |

### What the curve says

- **Below ~64 KB the transport is call-overhead-bound.** Every round-trip pays a fixed ~80 µs floor (Dart isolate scheduling + Python GIL acquisition + two `bridge.send_bytes` calls). At 1 KB this overhead swamps the byte work — 23 MB/s is the *call rate*, not the *memory rate*.
- **At 64 KB → 16 MB it scales linearly with payload size.** Throughput goes from 1.3 GB/s to 7.2 GB/s as the per-byte cost (memory copy + Dart Native API marshalling) dominates the fixed per-call cost.
- **7.2 GB/s at 16 MB is within an order of magnitude of M2 Pro's main-memory bandwidth ceiling** (~200 GB/s theoretical, ~50 GB/s achievable for non-tuned `memcpy`). Practically: the bridge is memory-copy-bound, which is the best you can do without a true zero-copy shared-buffer scheme.

For comparison: a Unix-domain socket transport on the same hardware tops out near 1 GB/s for similar-sized payloads, because every byte traverses the kernel.

## Memory

Methodology — 1 000 × 1 MB echo round-trips (~2 GB of bytes crossing the bridge total). Python heap measured via `tracemalloc.get_traced_memory()` (load-bearing leak signal — unit-stable, byte-accurate). RSS measured via `resource.getrusage(RUSAGE_SELF).ru_maxrss` on the Python side and `ProcessInfo.currentRss` on the Dart side (informational only — page residency, not retention).

| Metric                              | Before    | After     | Delta                                       |
|-------------------------------------|----------:|----------:|--------------------------------------------:|
| Python heap (`tracemalloc`)         |  10 179 B |  10 179 B |   **0 B**                                   |
| Python RSS (`ru_maxrss`)            |    350 MB |    457 MB |  +112 MB                                    |
| Dart RSS (`ProcessInfo.currentRss`) |  1 232 MB |  1 239 MB |  +7 MB                                      |
| Python `tracemalloc` peak           |  11 446 B |    1.0 MB |  +~1 MB (per-iteration buffer; reclaimed)   |

### What the deltas say

- **`traced_delta = 0 B` after 2 GB of throughput.** This is the only number that matters for "does the bridge leak?" — Python's heap accounting is exact down to the byte. Zero growth means **the bridge does not retain a single byte** of the data it transports.
- **`traced_peak` rose to ~1 MB** — exactly the size of one in-flight payload, then reclaimed. The bridge holds at most one frame's worth of bytes per direction.
- **RSS growth (Python +112 MB, Dart +7 MB) is OS-level page residency**, not retention. macOS keeps recently-faulted-in pages mapped for performance; the kernel will release them under pressure. This is normal behaviour for any process that has briefly touched a lot of memory, and is decoupled from actual ownership of bytes.

## Bottom line

| Concern                                     | Result                                                          |
|---------------------------------------------|-----------------------------------------------------------------|
| Speed at typical Flet message size (~KB)    | ~80 µs per round-trip (~12 000 messages/sec round-trip rate)    |
| Speed at "moving files / images" sizes (MB) | **4.5 GB/s at 1 MB, 7.2 GB/s at 16 MB** — memory-bandwidth class |
| Leaks?                                      | **None. 2 GB moved, Python heap unchanged.**                    |
| Bytes retained per round-trip               | Zero (peak ≤ 1 MB during one frame, then reclaimed)             |
