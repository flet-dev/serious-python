import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1000×1MB echo loop does not leak', (tester) async {
    final handle = await bootAndAwaitReady(tester);

    // First snapshot also primes tracemalloc on the Python side (the Python
    // handler starts tracemalloc lazily on first `mem` op). The very first
    // snapshot is intentionally discarded for the leak assertion so the
    // tracemalloc warm-up doesn't count against the heap delta.
    await memSnapshot(handle);

    // Now take the real baseline.
    final dartRssBefore = ProcessInfo.currentRss;
    final before = await memSnapshot(handle);

    // Hammer: 1000 × 1 MB round-trips through the echo channel. ~2 GB of
    // bytes crossing the bridge total. A leak retaining even ~1% of that
    // would show up well above noise in the after-snapshot.
    final rng = Random(0xBEEF);
    final payload = Uint8List.fromList(
        List<int>.generate(1024 * 1024, (_) => rng.nextInt(256)));
    for (var i = 0; i < 1000; i++) {
      await echoRoundTrip(handle, payload);
    }

    // Encourage Python to collect what it can before the second snapshot —
    // a noop if no garbage; cheap if there's any.
    handle.sendControl({'op': 'mem'}); // triggers another tracemalloc tick
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final after = await memSnapshot(handle);
    final dartRssAfter = ProcessInfo.currentRss;

    final tracedDelta = after.tracedCurrent - before.tracedCurrent;
    final rssDelta = after.rss - before.rss;
    final dartRssDelta = dartRssAfter - dartRssBefore;

    // ignore: avoid_print
    print('[bridge_mem] before=$before');
    // ignore: avoid_print
    print('[bridge_mem] after=$after');
    // ignore: avoid_print
    print('[bridge_mem] traced_delta=${tracedDelta}B '
        'rss_delta=${rssDelta}B '
        'dart_rss_delta=${dartRssDelta}B '
        '(dart_rss may be 0 on iOS/Android)');

    // tracemalloc is unit-stable (bytes) and is the load-bearing leak check.
    // 5 MB is generous: a per-iteration leak of 1 KB across 100 rounds would
    // be 100 KB, well within budget; a 5%+ leak of 1 MB payloads would not.
    expect(tracedDelta, lessThan(5 * 1024 * 1024),
        reason: 'Python heap grew >5MB across 100×1MB echo loop — '
            'likely a Python-side leak (libdart_bridge buffer retained, etc.)');

    // ru_maxrss has a unit quirk (kB on Linux/Android, bytes on macOS/iOS)
    // and is influenced by OS-level page allocation patterns, so we
    // log-only. Real assertion lives in tracedDelta above.
  });
}
