import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

class PackageCommand extends Command {
  @override
  final name = "package";

  @override
  final description = "Packages Python app to Flutter assets.";

  PackageCommand() {
    argParser.addOption('asset',
        abbr: 'a',
        help:
            "Asset path, relative to pubspec.yaml, to package Python program into.",
        mandatory: true);
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

    final sourceDir = Directory(argResults!.rest.first);

    if (!sourceDir.existsSync()) {
      stdout.writeln('Source directory does not exist.');
      exit(2);
    }

    Directory? tempDir;

    try {
      final currentPath = Directory.current.path;

      final pubspecFile = File(path.join(currentPath, "pubspec.yaml"));
      if (!pubspecFile.existsSync()) {
        stdout.writeln("Current directory must contain pubspec.yaml.");
        exit(1);
      }

      // delete dest archive
      final dest = File(path.join(currentPath, argResults?['asset']));
      dest.parent.createSync(recursive: true);

      // create temp dir
      tempDir = Directory.systemTemp.createTempSync('serious_python_temp');

      // copy app to a temp dir
      copyDirectory(sourceDir, tempDir);

      // discover dependencies
      List<String>? dependencies;
      final pyprojectFile = File(path.join(tempDir.path, 'pyproject.toml'));
      if (pyprojectFile.existsSync()) {
        final content = await pyprojectFile.readAsString();
        final document = TomlDocument.parse(content).toMap();
        dependencies = List<String>.from(
            document['tool']['poetry']['dependencies'].keys.map((key) =>
                '$key${document['tool']['poetry']['dependencies'][key]}'));
      } else {
        final requirementsFile =
            File(path.join(tempDir.path, 'requirements.txt'));
        if (requirementsFile.existsSync()) {
          dependencies = await requirementsFile.readAsLines();
        }
      }

      // install dependencies
      if (dependencies != null) {
        final pipProcess = await Process.start(
            'python3',
            [
              '-m',
              'pip',
              'install',
              '--isolated',
              '--upgrade',
              '--target',
              path.join(tempDir.path, '__pypackages__'),
              ...dependencies
            ],
            environment: {
              "CC": "/bin/false",
              "CXX": "/bin/false",
              "PYTHONPATH": tempDir.path,
              "PYTHONOPTIMIZE": "2",
            },
            runInShell: true,
            includeParentEnvironment: false);

        await for (final line in pipProcess.stdout.transform(utf8.decoder)) {
          stdout.write(line);
        }

        if (await pipProcess.exitCode != 0) {
          stdout.write(await pipProcess.stderr.transform(utf8.decoder).join());
          exit(1);
        }
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
      } else if (entity is File && entity.path.endsWith('.so')) {
        entity.deleteSync();
      }
    });

    directory.listSync().forEach((entity) {
      if (entity is Directory && entity.path.endsWith('__pycache__')) {
        entity.deleteSync(recursive: true);
      } else if (entity is Directory && entity.path.endsWith('bin')) {
        entity.deleteSync(recursive: true);
      }
    });
  }
}
