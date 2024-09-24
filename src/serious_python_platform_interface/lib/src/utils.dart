import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> extractAssetOrFile(String path,
    {bool isAsset = true, String? targetPath, bool checkHash = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  final documentsOrTempDir = (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)
      ? await getApplicationDocumentsDirectory()
      : await getTemporaryDirectory();
  final destDir = Directory(p.join(
      documentsOrTempDir.path,
      "${packageInfo.appName}-${packageInfo.version}-${packageInfo.buildNumber}",
      targetPath ?? p.dirname(path)));

  String assetHash = "";
  String destHash = "";
  var hashFile = File(p.join(destDir.path, ".hash"));

  // re-create dir
  if (await destDir.exists()) {
    if (kDebugMode) {
      // always re-create in debug mode
      await destDir.delete(recursive: true);
    } else {
      if (checkHash) {
        // read asset hash from asset
        try {
          assetHash = (await rootBundle.loadString("$path.hash")).trim();
          // ignore: empty_catches
        } catch (e) {}
        if (await hashFile.exists()) {
          destHash = (await hashFile.readAsString()).trim();
        }
      }

      if (assetHash != destHash) {
        await destDir.delete(recursive: true);
      } else {
        debugPrint("Application archive already unpacked.");
        return destDir.path;
      }
    }
  }
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
      archive = ZipDecoder().decodeBuffer(inputStream);
    }
    await extractArchiveToDiskAsync(archive, destDir.path, asyncWrite: true);
  } catch (e) {
    debugPrint("Error unpacking archive: $e");
    await destDir.delete(recursive: true);
    rethrow;
  }

  debugPrint("Finished unpacking application archive in ${stopwatch.elapsed}");

  if (checkHash) {
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
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  final documentsOrTempDir = (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)
      ? await getApplicationDocumentsDirectory()
      : await getTemporaryDirectory();

  // (re-)create destination directory
  var destDir = Directory(p.join(
      documentsOrTempDir.path,
      "${packageInfo.appName}-${packageInfo.version}-${packageInfo.buildNumber}",
      p.dirname(assetPath)));

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
