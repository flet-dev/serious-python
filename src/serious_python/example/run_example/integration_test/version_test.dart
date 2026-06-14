import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python/serious_python.dart';

/// Asserts the embedded Python runtime is the version we asked for. Pass the
/// expected short version via `--dart-define=EXPECTED_PYTHON_VERSION=3.x`.
///
/// The packaged app (app/src/main.py) imports numpy when `PYTHON_VERSION_FILENAME`
/// is set — a native-extension ABI canary that fails if the bundled interpreter
/// doesn't match the packaged cp<ver> wheels — then writes its short version to
/// that file. This is the regression guard for switching Python versions on one
/// machine (see .github/workflows/python-version-switching.yml).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('embedded Python matches EXPECTED_PYTHON_VERSION', (tester) async {
    const expected = String.fromEnvironment('EXPECTED_PYTHON_VERSION');
    expect(expected, isNotEmpty,
        reason: 'pass --dart-define=EXPECTED_PYTHON_VERSION=3.x');

    final tempDir = await Directory.systemTemp.createTemp('version_test');
    final versionFile = p.join(tempDir.path, 'pyversion.txt');

    unawaited(SeriousPython.run('app/app.zip',
        environmentVariables: {'PYTHON_VERSION_FILENAME': versionFile},
        sync: false));

    String? actual;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
      final f = File(versionFile);
      if (await f.exists()) {
        actual = (await f.readAsString()).trim();
        if (actual.isNotEmpty) break;
      }
    }

    expect(actual, expected,
        reason: 'the embedded interpreter (and its numpy wheel) should be the '
            'requested Python version');
  });
}
