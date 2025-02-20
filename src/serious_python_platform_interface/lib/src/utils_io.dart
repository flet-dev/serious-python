import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'utils_interface.dart';

class IOUtils implements PlatformUtils {
  @override
  Future<String> extractAssetOrFile(String path,
      {bool isAsset = true, String? targetPath, bool checkHash = false}) async {
    WidgetsFlutterBinding.ensureInitialized();
    final supportDir = await getApplicationSupportDirectory();
    final destDir = Directory(p.join(supportDir.path, "flet", targetPath ?? p.dirname(path)));

    String assetHash = "";
    String destHash = "";
    var hashFile = File(p.join(destDir.path, ".hash"));

    if (await destDir.exists()) {
      if (kDebugMode) {
        await destDir.delete(recursive: true);
      } else if (checkHash) {
        try {
          assetHash = (await rootBundle.loadString("$path.hash")).trim();
        } catch (e) {
          assetHash = "";
        }

        if (await hashFile.exists()) {
          destHash = (await hashFile.readAsString()).trim();
        }

        if (assetHash != destHash || (checkHash && assetHash.isEmpty && destHash.isEmpty)) {
          await destDir.delete(recursive: true);
        } else {
          return destDir.path;
        }
      }
    }

    await _extractArchive(path, destDir, isAsset);

    if (checkHash) {
      await hashFile.writeAsString(assetHash);
    }

    return destDir.path;
  }

  Future<void> _extractArchive(String path, Directory destDir, bool isAsset) async {
    await destDir.create(recursive: true);

    try {
      Archive archive;
      if (isAsset) {
        final bytes = await rootBundle.load(path);
        var data = bytes.buffer.asUint8List();
        archive = ZipDecoder().decodeBytes(data);
      } else {
        final inputStream = InputFileStream(path);
        archive = ZipDecoder().decodeBuffer(inputStream);
      }
      await extractArchiveToDiskAsync(archive, destDir.path, asyncWrite: true);
    } catch (e) {
      debugPrint("Error unpacking archive: $e");
      await destDir.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<String> extractAssetZip(String assetPath, {String? targetPath, bool checkHash = false}) {
    return extractAssetOrFile(assetPath, targetPath: targetPath, checkHash: checkHash);
  }

  @override
  Future<String> extractFileZip(String filePath, {String? targetPath, bool checkHash = false}) {
    return extractAssetOrFile(filePath, isAsset: false, targetPath: targetPath, checkHash: checkHash);
  }

  @override
  Future<String> extractAsset(String assetPath) async {
    WidgetsFlutterBinding.ensureInitialized();
    final supportDir = await getApplicationSupportDirectory();
    final destDir = Directory(p.join(supportDir.path, "flet", p.dirname(assetPath)));
    await destDir.create(recursive: true);

    var destPath = p.join(destDir.path, p.basename(assetPath));
    if (kDebugMode && await File(destPath).exists()) {
      await File(destPath).delete();
    }

    ByteData data = await rootBundle.load(assetPath);
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(destPath).writeAsBytes(bytes);
    return destPath;
  }

  @override
  Future<String> getDirFiles(String path, {bool recursive = false}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return "<not found>";
    }
    return (await dir.list(recursive: recursive).toList()).map((file) => file.path).join('\n');
  }
}

PlatformUtils getPlatformUtils() => IOUtils();
