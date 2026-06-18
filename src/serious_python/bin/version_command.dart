import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:package_config/package_config.dart';
import 'package:serious_python/src/python_versions.dart';

/// `version` subcommand: prints the serious_python package version, the
/// default Python version, and the supported-Python matrix sourced from
/// [pythonReleases] in the generated `lib/src/python_versions.dart`. With
/// `--json`, emits a machine-readable document for CI / tooling consumption.
class VersionCommand extends Command {
  @override
  final name = "version";

  @override
  final description =
      "Print serious_python version and the supported Python matrix.";

  VersionCommand() {
    argParser.addFlag(
      "json",
      help: "Emit machine-readable JSON instead of the human-readable summary.",
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final version = await _readSeriousPythonVersion() ?? "unknown";
    final jsonMode = argResults?["json"] ?? false;

    if (jsonMode) {
      final doc = <String, dynamic>{
        "serious_python_version": version,
        "python_build_release_date": pythonReleaseDate,
        "default_python_version": defaultPythonVersion,
        "dart_bridge_version": dartBridgeVersion,
        "python_releases": <String, dynamic>{
          for (final entry in pythonReleases.entries)
            entry.key: {
              "standalone_version": entry.value.standaloneVersion,
              "standalone_release_date": entry.value.standaloneReleaseDate,
              "pyodide_version": entry.value.pyodideVersion,
              "pyodide_platform_tag": entry.value.pyodidePlatformTag,
              "prerelease": entry.value.prerelease,
            },
        },
      };
      stdout.writeln(const JsonEncoder.withIndent("  ").convert(doc));
      return;
    }

    stdout.writeln("serious_python $version");
    stdout.writeln("Default Python: $defaultPythonVersion");
    stdout.writeln("Supported Python versions:");
    // Sort descending so the default + newest stable is on top, matching the
    // ordering convention used by `flet --version`.
    final keys = pythonReleases.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (final k in keys) {
      final r = pythonReleases[k]!;
      final markers = <String>[];
      if (k == defaultPythonVersion) markers.add("default");
      if (r.prerelease) markers.add("pre-release");
      final markerSuffix = markers.isEmpty ? "" : " (${markers.join(", ")})";
      stdout.writeln(
          "  $k$markerSuffix: CPython ${r.standaloneVersion} / Pyodide ${r.pyodideVersion}");
    }
  }

  /// Read this package's `version:` from its `pubspec.yaml`, found via the
  /// caller's `package_config.json`. Returns `null` if the package_config
  /// can't be located (e.g. invoked from a compiled snapshot outside any
  /// pub workspace).
  Future<String?> _readSeriousPythonVersion() async {
    final config = await findPackageConfig(Directory.current);
    final pkg = config?["serious_python"];
    if (pkg == null) return null;
    final pubspec = File.fromUri(pkg.root.resolve("pubspec.yaml"));
    if (!pubspec.existsSync()) return null;
    final versionPattern = RegExp(r'^version:\s*(\S+)\s*$');
    for (final line in pubspec.readAsLinesSync()) {
      final match = versionPattern.firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }
}
