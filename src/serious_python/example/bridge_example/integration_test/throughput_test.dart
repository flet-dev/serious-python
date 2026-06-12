import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // (payloadBytes, iterations) — sizes go up to 16 MB; iteration count drops
  // for bigger payloads so total wall-time stays bounded (~30 s on macOS).
  const sizes = <(int, int)>[
    (1024, 100),
    (64 * 1024, 100),
    (256 * 1024, 100),
    (1024 * 1024, 100),
    (4 * 1024 * 1024, 100),
    (16 * 1024 * 1024, 100),
  ];

  testWidgets('echo channel throughput across size sweep', (tester) async {
    final handle = await bootAndAwaitReady(tester);
    for (final (size, iterations) in sizes) {
      final rng = Random(0xC0FFEE ^ size);
      final payload =
          Uint8List.fromList(List<int>.generate(size, (_) => rng.nextInt(256)));

      // Verify byte identity once per size; per-iteration assert would
      // dominate the timing measurement.
      final first = await echoRoundTrip(handle, payload);
      expect(first, equals(payload),
          reason: 'echo mutated payload at size=$size');

      final samples = <int>[]; // microseconds per round-trip
      for (var i = 0; i < iterations; i++) {
        final sw = Stopwatch()..start();
        await echoRoundTrip(handle, payload);
        sw.stop();
        samples.add(sw.elapsedMicroseconds);
      }

      samples.sort();
      final min = samples.first;
      final p50 = samples[samples.length ~/ 2];
      final p95 =
          samples[(samples.length * 95 ~/ 100).clamp(0, samples.length - 1)];
      final mean = samples.reduce((a, b) => a + b) / samples.length;

      // Throughput in MB/s based on the mean. A round-trip moves 2×size
      // bytes through the bridge (Dart→Py + Py→Dart).
      final meanSeconds = mean / 1e6;
      final mbPerSec = (2 * size) / (meanSeconds * 1024 * 1024);

      // ignore: avoid_print
      print('[bridge_perf] size=$size N=$iterations '
          'min=${(min / 1000).toStringAsFixed(2)}ms '
          'p50=${(p50 / 1000).toStringAsFixed(2)}ms '
          'p95=${(p95 / 1000).toStringAsFixed(2)}ms '
          'mean=${(mean / 1000).toStringAsFixed(2)}ms '
          'throughput=${mbPerSec.toStringAsFixed(1)}MB/s');

      // Order-of-magnitude floor — catches >5× regressions without flaking
      // on slow Windows Debug runs. Tune after a stable week.
      if (size >= 1024 * 1024) {
        expect(mbPerSec, greaterThan(50),
            reason: 'echo throughput dropped below floor at size=$size');
      }
    }
  });
}
