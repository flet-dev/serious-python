import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final Map<String, Future<void>> _extractQueues = {};

Future<String> extractAssetOrFile(String path,
    {bool isAsset = true,
    String? targetPath,
    bool checkHash = false,
    String? invalidateKey}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final destDir =
      Directory(p.join(supportDir.path, "flet", targetPath ?? p.dirname(path)));

  return _withExtractQueue(destDir.path, () {
    return _extractAssetOrFileLocked(path,
        isAsset: isAsset,
        checkHash: checkHash,
        invalidateKey: invalidateKey,
        destDir: destDir);
  });
}

Future<T> _withExtractQueue<T>(String key, Future<T> Function() action) async {
  final previous = _extractQueues[key] ?? Future<void>.value();
  final current = previous.then((_) => action());
  final barrier = current.then<void>((_) {}, onError: (_) {});
  _extractQueues[key] = barrier;
  unawaited(barrier.whenComplete(() {
    if (identical(_extractQueues[key], barrier)) {
      _extractQueues.remove(key);
    }
  }));
  return current;
}

Future<String> _extractAssetOrFileLocked(String path,
    {required bool isAsset,
    required bool checkHash,
    required Directory destDir,
    String? invalidateKey}) async {
  var invalidateFile = File(p.join(destDir.path, ".invalidate"));
  String existingInvalidateKey = "";

  String assetHash = "";
  // read asset hash from asset
  try {
    assetHash = (await rootBundle.loadString("$path.hash")).trim();
    // ignore: empty_catches
  } catch (e) {}

  List<int>? archiveBytes;
  if ((kDebugMode || checkHash) && assetHash.isEmpty) {
    archiveBytes = await _readArchiveBytes(path, isAsset: isAsset);
    assetHash = _fingerprintBytes(archiveBytes);
  }

  String destHash = "";
  var hashFile = File(p.join(destDir.path, ".hash"));

  // re-create dir
  if (await destDir.exists()) {
    var shouldReplace = false;

    if (invalidateKey != null) {
      if (await invalidateFile.exists()) {
        existingInvalidateKey = (await invalidateFile.readAsString()).trim();
      }
      if (existingInvalidateKey != invalidateKey) {
        shouldReplace = true;
      }
    }

    if (!shouldReplace) {
      if (assetHash.isNotEmpty || checkHash) {
        if (await hashFile.exists()) {
          destHash = (await hashFile.readAsString()).trim();
        }
      }

      if (assetHash.isNotEmpty) {
        shouldReplace = assetHash != destHash;
      } else if (checkHash) {
        shouldReplace = true;
      }
    }

    if (!shouldReplace) {
      debugPrint("Application archive already unpacked to ${destDir.path}");
      return destDir.path;
    }

    try {
      await _moveExistingDirectoryAside(destDir);
    } on FileSystemException catch (e) {
      if (!kDebugMode) {
        rethrow;
      }
      debugPrint(
          "Could not replace ${destDir.path}; using existing extraction: $e");
      return destDir.path;
    }
  }

  debugPrint("extractAssetOrFile directory: ${destDir.path}");
  await destDir.create(recursive: true);

  // unpack from asset or file
  debugPrint("Start unpacking archive: $path");
  Stopwatch stopwatch = Stopwatch()..start();

  try {
    Archive archive;
    if (isAsset) {
      final bytes = archiveBytes ?? await _readArchiveBytes(path);
      archive = ZipDecoder().decodeBytes(bytes);
    } else if (archiveBytes != null) {
      archive = ZipDecoder().decodeBytes(archiveBytes);
    } else {
      final inputStream = InputFileStream(path);
      archive = ZipDecoder().decodeStream(inputStream);
    }
    await extractArchiveToDisk(archive, destDir.path);
  } catch (e) {
    debugPrint("Error unpacking archive: $e");
    await _deleteDirectoryBestEffort(destDir);
    rethrow;
  }

  debugPrint("Finished unpacking application archive in ${stopwatch.elapsed}");

  if (assetHash.isNotEmpty && (checkHash || kDebugMode)) {
    debugPrint("Writing hash file: ${hashFile.path}, hash: $assetHash");
    await hashFile.writeAsString(assetHash);
  }

  if (invalidateKey != null) {
    debugPrint(
        "Writing invalidate file: ${invalidateFile.path}, key: $invalidateKey");
    await invalidateFile.writeAsString(invalidateKey);
  }

  return destDir.path;
}

Future<List<int>> _readArchiveBytes(String path, {bool isAsset = true}) async {
  if (!isAsset) {
    return File(path).readAsBytes();
  }
  final bytes = await rootBundle.load(path);
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

String _fingerprintBytes(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return "${bytes.length}-${hash.toRadixString(16).padLeft(8, '0')}";
}

Future<void> _moveExistingDirectoryAside(Directory destDir) async {
  final parent = destDir.parent;
  final basename = p.basename(destDir.path);
  final staleDir = Directory(p.join(parent.path,
      ".$basename.${DateTime.now().microsecondsSinceEpoch}.stale"));
  final movedDir = await destDir.rename(staleDir.path);
  unawaited(_deleteDirectoryBestEffort(movedDir));
}

Future<void> _deleteDirectoryBestEffort(Directory dir) async {
  try {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e) {
    debugPrint("Could not delete ${dir.path}: $e");
  }
}

Future<String> extractAssetZip(String assetPath,
    {String? targetPath, bool checkHash = false, String? invalidateKey}) async {
  return extractAssetOrFile(assetPath,
      targetPath: targetPath,
      checkHash: checkHash,
      invalidateKey: invalidateKey);
}

Future<String> extractFileZip(String filePath,
    {String? targetPath, bool checkHash = false, String? invalidateKey}) async {
  return extractAssetOrFile(filePath,
      isAsset: false,
      targetPath: targetPath,
      checkHash: checkHash,
      invalidateKey: invalidateKey);
}

Future<String> extractAsset(String assetPath) async {
  WidgetsFlutterBinding.ensureInitialized();

  // (re-)create destination directory
  final supportDir = await getApplicationSupportDirectory();
  final destDir =
      Directory(p.join(supportDir.path, "flet", p.dirname(assetPath)));

  await destDir.create(recursive: true);

  // extract file from assets
  var destPath = p.join(destDir.path, p.basename(assetPath));
  if (kDebugMode && await File(destPath).exists()) {
    await File(destPath).delete();
  }
  ByteData data = await rootBundle.load(assetPath);
  List<int> bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await File(destPath).writeAsBytes(bytes);
  return destPath;
}

Future<String> getDirFiles(String path, {bool recursive = false}) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    return "<not found>";
  }
  return (await dir.list(recursive: recursive).toList())
      .map((file) => file.path)
      .join('\n');
}
