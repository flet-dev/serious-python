import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('dest', abbr: 'd', help: 'destination archive path and name');
  //..addPositional('source', help: 'source directory path');

  final args = parser.parse(arguments);

  if (args.rest.isEmpty) {
    stdout.writeln("Usage:");
    stdout.writeln(
        "  flutter pub run serious_python:package [options] <source_dir>\n");
    stdout.writeln("Options:");
    stdout.writeln(parser.usage);
    exit(1);
  }

  final sourceDir = Directory(args['source']);
  final dest = File(args['dest']);

  if (!sourceDir.existsSync()) {
    stdout.writeln('Source directory does not exist');
    exit(2);
  }

  final tempDir = Directory.systemTemp.createTempSync('copy_and_zip');
  copyDirectory(sourceDir, tempDir);

  List<String>? dependencies;
  final pyprojectFile = File(path.join(tempDir.path, 'pyproject.toml'));
  if (pyprojectFile.existsSync()) {
    final content = await pyprojectFile.readAsString();
    final document = TomlDocument.parse(content).toMap();
    dependencies = List<String>.from(document['tool']['poetry']['dependencies']
        .keys
        .map(
            (key) => '$key${document['tool']['poetry']['dependencies'][key]}'));
  } else {
    final requirementsFile = File(path.join(tempDir.path, 'requirements.txt'));
    if (requirementsFile.existsSync()) {
      dependencies = await requirementsFile.readAsLines();
    }
  }

  if (dependencies != null) {
    final pipProcess = await Process.start(
        'pip3',
        [
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

  deleteDirectories(tempDir);

  final encoder = ZipFileEncoder();
  encoder.zipDirectory(tempDir, filename: dest.path);
}

void copyDirectory(Directory source, Directory destination) {
  source.listSync().forEach((entity) {
    if (entity is Directory) {
      final newDirectory =
          Directory(path.join(destination.path, path.basename(entity.path)));
      newDirectory.createSync();
      copyDirectory(entity.absolute, newDirectory);
    } else if (entity is File) {
      entity.copySync(path.join(destination.path, path.basename(entity.path)));
    }
  });
}

void deleteDirectories(Directory directory) {
  directory.listSync().forEach((entity) {
    if (entity is Directory) {
      deleteDirectories(entity);
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
