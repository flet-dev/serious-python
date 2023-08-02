import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

const junkFileExtensions = [".so", ".py", ".c", ".typed"];
const junkFilesAndDirectories = ["__pycache__", "bin"];

class PackageCommand extends Command {
  @override
  final name = "package";

  @override
  final description = "Packages Python app to Flutter assets.";

  PackageCommand() {
    argParser.addFlag("pre",
        help: "Install pre-release dependencies.", negatable: false);
    argParser.addOption('asset',
        abbr: 'a',
        help:
            "Asset path, relative to pubspec.yaml, to package Python program into.");
  }

  // [run] may also return a Future.
  @override
  Future run() async {
    if (argResults == null ||
        argResults?.rest == null ||
        argResults!.rest.isEmpty) {
      stdout.writeln(("Error: Source directory is not provided."));
      stdout.writeln(usage);
      exit(1);
    }

    Directory? tempDir;

    try {
      final currentPath = Directory.current.path;

      // source dir
      var sourceDirPath = argResults!.rest.first;

      if (path.isRelative(sourceDirPath)) {
        sourceDirPath = path.join(currentPath, sourceDirPath);
      }

      final sourceDir = Directory(sourceDirPath);

      if (!sourceDir.existsSync()) {
        stdout.writeln('Source directory does not exist.');
        exit(2);
      }

      final pubspecFile = File(path.join(currentPath, "pubspec.yaml"));
      if (!pubspecFile.existsSync()) {
        stdout.writeln("Current directory must contain pubspec.yaml.");
        exit(1);
      }

      // asset path
      var assetPath = argResults?['asset'];
      if (assetPath == null) {
        assetPath = "app/app.zip";
      } else if (assetPath.startsWith("/") || assetPath.startsWith("\\")) {
        assetPath = assetPath.substring(1);
      }

      // delete dest archive
      final dest = File(path.join(currentPath, assetPath));
      dest.parent.createSync(recursive: true);

      // create temp dir
      tempDir = Directory.systemTemp.createTempSync('serious_python_temp');

      // copy app to a temp dir
      copyDirectory(sourceDir, tempDir);

      // discover dependencies
      List<String>? dependencies;
      final requirementsFile =
          File(path.join(tempDir.path, 'requirements.txt'));
      final pyprojectFile = File(path.join(tempDir.path, 'pyproject.toml'));
      if (requirementsFile.existsSync()) {
        dependencies = await requirementsFile.readAsLines();
      } else if (pyprojectFile.existsSync()) {
        final content = await pyprojectFile.readAsString();
        final document = TomlDocument.parse(content).toMap();
        var depSection = findTomlDependencies(document);
        if (depSection != null) {
          if (depSection is List) {
            dependencies = depSection.map((e) => e.toString()).toList();
          } else {
            stdout.writeln(
                "Warning: [dependencies] section of map type is not yet supported.");
            // dependencies = List<String>.from(
            //     depSection.keys.map((key) => '$key=${depSection[key]}'));
          }
        }
      }

      // install dependencies
      if (dependencies != null) {
        dependencies = dependencies
            .map((d) => d.replaceAllMapped(RegExp(r'flet(\W{1,}|$)'),
                (match) => 'flet-embed${match.group(1)}'))
            .toList();

        List<String> extraArgs = [];
        if (argResults?["pre"]) {
          extraArgs.add("--pre");
        }

        await runPython([
          '-m',
          'pip',
          'install',
          '--isolated',
          '--upgrade',
          ...extraArgs,
          '--target',
          path.join(tempDir.path, '__pypackages__'),
          ...dependencies
        ], environment: {
          "CC": "/bin/false",
          "CXX": "/bin/false",
          "PYTHONPATH": tempDir.path,
          "PYTHONOPTIMIZE": "2",
        });

        // compile all python code
        await runPython(['-m', 'compileall', '-b', tempDir.path]);
      }

      // remove unnecessary files
      cleanupPyPackages(tempDir);

      // create archive
      final encoder = ZipFileEncoder();
      encoder.zipDirectory(tempDir, filename: dest.path);
    } catch (e) {
      stdout.writeln("Error: $e");
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  dynamic findTomlDependencies(Map<String, dynamic> section) {
    if (section.containsKey('dependencies')) {
      return section['dependencies'];
    }

    for (final value in section.values) {
      if (value is Map<String, dynamic>) {
        final dependencies = findTomlDependencies(value);
        if (dependencies != null) {
          return dependencies;
        }
      }
    }

    return null;
  }

  void copyDirectory(Directory source, Directory destination) {
    source.listSync().forEach((entity) {
      if (entity is Directory) {
        final newDirectory =
            Directory(path.join(destination.path, path.basename(entity.path)));
        newDirectory.createSync();
        copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        entity
            .copySync(path.join(destination.path, path.basename(entity.path)));
      }
    });
  }

  void cleanupPyPackages(Directory directory) {
    directory.listSync().forEach((entity) {
      if (entity is Directory) {
        cleanupPyPackages(entity);
      } else if (entity is File &&
              junkFileExtensions.contains(path.extension(entity.path)) ||
          junkFilesAndDirectories.contains(path.basename(entity.path))) {
        stdout.writeln("Deleting ${entity.path}");
        entity.deleteSync();
      }
    });

    directory.listSync().forEach((entity) {
      if (entity is Directory &&
          junkFilesAndDirectories.contains(path.basename(entity.path))) {
        stdout.writeln("Deleting ${entity.path}");
        entity.deleteSync(recursive: true);
      }
    });
  }

  Future<int> runExec(String execPath, List<String> args,
      {Map<String, String>? environment}) async {
    final proc = await Process.start(execPath, args,
        environment: environment,
        runInShell: true,
        includeParentEnvironment: false);

    await for (final line in proc.stdout.transform(utf8.decoder)) {
      stdout.write(line);
    }

    if (await proc.exitCode != 0) {
      stdout.write(await proc.stderr.transform(utf8.decoder).join());
      exit(1);
    }
    return proc.exitCode;
  }

  Future runPython(List<String> args,
      {Map<String, String>? environment}) async {
    var pythonDir =
        Directory(path.join(Directory.systemTemp.path, "hostpython3.10"));

    if (!await pythonDir.exists()) {
      stdout
          .writeln("Downloading and extracting Python into ${pythonDir.path}");

      var isArm64 = Platform.version.contains("arm64");

      String arch = "";
      if (Platform.isMacOS && !isArm64) {
        arch = 'x86_64-apple-darwin';
      } else if (Platform.isMacOS && isArm64) {
        arch = 'aarch64-apple-darwin';
      } else if (Platform.isLinux) {
        arch = 'x86_64-unknown-linux-gnu';
      } else if (Platform.isWindows) {
        arch = 'x86_64-pc-windows-msvc-shared';
      }

      final url =
          "https://github.com/indygreg/python-build-standalone/releases/download/20230507/cpython-3.10.11+20230507-$arch-install_only.tar.gz";

      await pythonDir.create(recursive: true);

      // Download the release asset
      var response = await http.get(Uri.parse(url));
      var archivePath = path.join(pythonDir.path, 'python.tar.gz');
      await File(archivePath).writeAsBytes(response.bodyBytes);

      // Extract the archive
      await Process.run('tar', ['-xzf', archivePath, '-C', pythonDir.path]);
    } else {
      stdout.writeln("Python has already downloaded to ${pythonDir.path}");
    }

    // Run the python executable
    var pythonPath = Platform.isWindows
        ? path.join(pythonDir.path, 'python', 'python.exe')
        : path.join(pythonDir.path, 'python', 'bin', 'python3');
    return await runExec(pythonPath, args, environment: environment);
  }
}
