import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:serious_python/src/python_versions.dart';

import 'package_command.dart' show stageDarwinRuntime, sitePackagesEnvironmentVariable;

/// `configure` subcommand: stages the embedded Python runtime for a platform and
/// version without packaging an app. Useful when running a bare Python script
/// (no `package` step) and to make a version switch take effect on a rebuild.
///
/// Only Darwin (iOS/macOS) needs explicit staging — the Android/Linux/Windows
/// native builds download the runtime themselves from the version table.
class ConfigureCommand extends Command {
  @override
  final name = "configure";

  @override
  final description =
      "Stage the embedded Python runtime for a platform/version (Darwin).";

  ConfigureCommand() {
    argParser.addOption('platform',
        abbr: "p",
        allowed: ["iOS", "Android", "Emscripten", "Windows", "Linux", "Darwin"],
        mandatory: true,
        help: "Platform to stage the runtime for, e.g. 'iOS' or 'Darwin'.");
    argParser.addOption('python-version',
        allowed: pythonReleases.keys.toList(),
        help: "Short Python version to stage (e.g. 3.13). Defaults to "
            "\$$pythonVersionEnvironmentVariable env var or "
            "'$defaultPythonVersion'.");
  }

  @override
  Future<void> run() async {
    final platform = argResults!['platform'] as String;
    final shortVersion = (argResults!['python-version'] as String?) ??
        Platform.environment[pythonVersionEnvironmentVariable] ??
        defaultPythonVersion;

    if (platform != "iOS" && platform != "Darwin") {
      stdout.writeln("configure: nothing to stage for $platform — its native "
          "build downloads the runtime from python_versions.properties.");
      return;
    }

    final sitePackagesRoot =
        Platform.environment[sitePackagesEnvironmentVariable];
    if (sitePackagesRoot == null || sitePackagesRoot.trim().isEmpty) {
      stderr.writeln("serious_python: set $sitePackagesEnvironmentVariable to "
          "the app's site-packages directory before running configure.");
      exit(2);
    }

    await stageDarwinRuntime(
      platform: platform,
      shortVersion: shortVersion,
      sitePackagesRoot: sitePackagesRoot,
    );
  }
}
