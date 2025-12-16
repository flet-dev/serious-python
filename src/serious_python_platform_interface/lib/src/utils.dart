import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> extractAssetOrFile(String path,
    {bool isAsset = true, String? targetPath, bool checkHash = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final destDir =
      Directory(p.join(supportDir.path, "flet", targetPath ?? p.dirname(path)));

  String assetHash = "";
  // read asset hash from asset
  try {
    assetHash = (await rootBundle.loadString("$path.hash")).trim();
    // ignore: empty_catches
  } catch (e) {}

  String destHash = "";
  var hashFile = File(p.join(destDir.path, ".hash"));

  // re-create dir
  if (await destDir.exists()) {
    if (kDebugMode) {
      // always re-create in debug mode
      await destDir.delete(recursive: true);
    } else {
      if (checkHash) {
        if (await hashFile.exists()) {
          destHash = (await hashFile.readAsString()).trim();
        }
      }

      if (assetHash != destHash ||
          (checkHash && assetHash == "" && destHash == "")) {
        await destDir.delete(recursive: true);
      } else {
        debugPrint("Application archive already unpacked to ${destDir.path}");
        return destDir.path;
      }
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
      final bytes = await rootBundle.load(path);
      var data = bytes.buffer.asUint8List();
      archive = ZipDecoder().decodeBytes(data);
    } else {
      final inputStream = InputFileStream(path);
      archive = ZipDecoder().decodeStream(inputStream);
    }
    await extractArchiveToDisk(archive, destDir.path);
  } catch (e) {
    debugPrint("Error unpacking archive: $e");
    await destDir.delete(recursive: true);
    rethrow;
  }

  debugPrint("Finished unpacking application archive in ${stopwatch.elapsed}");

  if (checkHash) {
    debugPrint("Writing hash file: ${hashFile.path}, hash: $assetHash");
    await hashFile.writeAsString(assetHash);
  }

  return destDir.path;
}

Future<String> extractAssetZip(String assetPath,
    {String? targetPath, bool checkHash = false}) async {
  return extractAssetOrFile(assetPath,
      targetPath: targetPath, checkHash: checkHash);
}

Future<String> extractFileZip(String filePath,
    {String? targetPath, bool checkHash = false}) async {
  return extractAssetOrFile(filePath,
      isAsset: false, targetPath: targetPath, checkHash: checkHash);
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
