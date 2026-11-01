import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Python ships on every GitHub-hosted runner, as `python` on Windows.
final python = Platform.isWindows ? "python" : "python3";

/// Longer than any case needs; a command that blocks on a full pipe never
/// finishes, so it fails here instead of hanging the test run.
const hangTimeout = Duration(seconds: 30);

late Directory tempDir;
late String harness;

/// Runs [script] with Python through `runExec`, inside the compiled harness.
Future<ProcessResult> runExec(String script) async {
  final proc = await Process.start(harness, [python, "-c", script]);
  final stdoutText = proc.stdout.transform(systemEncoding.decoder).join();
  final stderrText = proc.stderr.transform(systemEncoding.decoder).join();
  final status = await proc.exitCode.timeout(hangTimeout, onTimeout: () {
    proc.kill(ProcessSignal.sigkill);
    fail("runExec didn't return within $hangTimeout");
  });
  return ProcessResult(proc.pid, status, await stdoutText, await stderrText);
}

void main() {
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp("run_exec_test");
    harness =
        path.join(tempDir.path, Platform.isWindows ? "harness.exe" : "harness");
    final compile = await Process.run(
        "dart",
        [
          "compile",
          "exe",
          "test/fixtures/run_exec_harness.dart",
          "-o",
          harness,
        ],
        runInShell: true);
    expect(compile.exitCode, 0, reason: "${compile.stdout}${compile.stderr}");
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  // 200 KB is more than a pipe holds on any OS (about 1 KB on Windows,
  // 64 KB on macOS and Linux).

  test("a command writing a lot to stderr finishes, and its output is hidden",
      () async {
    final result = await runExec(
        "import sys; sys.stderr.write('w' * 200000); print('done')");

    expect(result.exitCode, 0);
    expect(result.stdout, contains("runExec returned 0"));
    expect(result.stderr, isEmpty);
  });

  test("a failing command's stdout and stderr are shown", () async {
    final result = await runExec("import sys; print('OUT-MARK'); "
        "sys.stderr.write('e' * 200000 + 'ERR-MARK'); sys.exit(3)");

    expect(result.exitCode, 1);
    expect(result.stderr, contains("OUT-MARK"));
    expect(result.stderr, contains("ERR-MARK"));
  });

  test("a command reading stdin gets end of input", () async {
    final result = await runExec(
        "import sys; data = sys.stdin.read(); sys.exit(0 if data == '' else 1)");

    expect(result.exitCode, 0);
    expect(result.stdout, contains("runExec returned 0"));
  });

  test("output that isn't UTF-8 is shown", () async {
    final result = await runExec("import sys; "
        "sys.stdout.buffer.write(b'caf\\xe9 BAD-BYTES'); sys.exit(2)");

    expect(result.exitCode, 1);
    expect(result.stderr, contains("BAD-BYTES"));
  });

  test("a process left running with the pipes open doesn't block", () async {
    // The process outlives hangTimeout, so waiting for its pipes to close
    // fails the test.
    final result = await runExec("import subprocess, sys; "
        "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])");

    expect(result.exitCode, 0);
    expect(result.stdout, contains("runExec returned 0"));
  });
}
