import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

Future<void> mergeMacOsSitePackages(String arm64Path, String x86_64Path,
    String targetPath, bool verbose) async {
  final arm64Dir = Directory(arm64Path);
  final x86_64Dir = Directory(x86_64Path);
  final targetDir = Directory(targetPath);

  // Create the target directory if it doesn't exist
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  // Merge the directories
  if (await x86_64Dir.exists() && !(await arm64Dir.exists())) {
    stdout.writeln('Copying macOS x86_64 site-packages');
    await copyDirectory(x86_64Dir, targetDir);
  } else if (await arm64Dir.exists() && !(await x86_64Dir.exists())) {
    stdout.writeln('Copying macOS arm64 site-packages');
    await copyDirectory(arm64Dir, targetDir);
  } else if (await arm64Dir.exists() && await x86_64Dir.exists()) {
    stdout.writeln('Merging macOS arm64 and x86_64 site-packages');
    await mergeDirs(arm64Dir, x86_64Dir, targetDir, verbose);
  } else {
    stdout.writeln('Cannot merge macOS packages. No arch directories found.');
    exit(1);
  }

  if (await arm64Dir.exists()) {
    await arm64Dir.delete(recursive: true);
  }

  if (await x86_64Dir.exists()) {
    await x86_64Dir.delete(recursive: true);
  }

  stdout.writeln('Merging completed successfully.');
}

Future<void> mergeDirs(Directory arm64Dir, Directory x86_64Dir,
    Directory targetDir, bool verbose) async {
  // Create the destination directory if it doesn't exist
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  // Iterate over the items in the arm64 directory
  await for (var item in arm64Dir.list(recursive: true)) {
    final x8664Itempath = path.join(
        x86_64Dir.path, path.relative(item.path, from: arm64Dir.path));
    final targetItemPath = path.join(
        targetDir.path, path.relative(item.path, from: arm64Dir.path));

    if (item is File) {
      if (!await File(targetItemPath).parent.exists()) {
        await File(targetItemPath).parent.create(recursive: true);
      }
      if (item.path.endsWith('.so')) {
        if (await isUniversalBinary(item.path)) {
          if (verbose) {
            stdout.writeln(
                '${item.path} is already a universal binary. Copying...');
          }
          await item.copy(targetItemPath);
        } else if (await isUniversalBinary(x8664Itempath)) {
          if (verbose) {
            stdout.writeln(
                '${item.path} is already a universal binary. Copying...');
          }
          await File(x8664Itempath).copy(targetItemPath);
        } else {
          if (verbose) {
            stdout.writeln("Lipo'ing ${item.path} and $x8664Itempath...");
          }
          await lipo(item.path, x8664Itempath, targetItemPath);
        }
      } else {
        // Copy non-.so files
        if (verbose) {
          stdout.writeln('Copying ${item.path}...');
        }
        await item.copy(targetItemPath);
      }
    }
  }
}

Future<void> copyDirectory(Directory source, Directory destination) async {
  stdout.writeln("Copy directory ${source.path} to ${destination.path}");
  if (!await destination.exists()) {
    await destination.create(recursive: true);
  }

  await for (var entity in source.list(recursive: true)) {
    final relativePath = entity.uri.path.substring(source.uri.path.length);
    final newPath = '${destination.path}/$relativePath';
    if (entity is Directory) {
      await Directory(newPath).create(recursive: true);
    } else if (entity is File) {
      await entity.copy(newPath);
    }
  }
}

Future<bool> isUniversalBinary(String filePath) async {
  final result = await Process.run('file', [filePath]);
  return result.stdout.contains('arm64') && result.stdout.contains('x86_64');
}

Future<void> lipo(
    String arm64Path, String x86_64Path, String outputPath) async {
  await Process.run(
      'lipo', ['-create', '-output', outputPath, arm64Path, x86_64Path]);
}
