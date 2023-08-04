import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> extractAssetOrFile(String path,
    {bool isAsset = true, String? targetPath}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final documentsDir = await getApplicationDocumentsDirectory();
  final destDir =
      Directory(p.join(documentsDir.path, targetPath ?? p.dirname(path)));

  // re-create dir
  if (await destDir.exists()) {
    if (kDebugMode) {
      // always re-create in debug mode
      await destDir.delete(recursive: true);
    } else {
      debugPrint("Application archive already unpacked.");
      return destDir.path;
    }
  }
  await destDir.create();

  // unpack from asset or file
  debugPrint("Start unpacking app archive");
  List<int> data;

  try {
    if (isAsset) {
      final bytes = await rootBundle.load(path);
      data = bytes.buffer.asUint8List();
    } else {
      data = await File(path).readAsBytes();
    }
  } catch (_) {
    await destDir.delete(recursive: true);
    rethrow;
  }

  Archive archive = ZipDecoder().decodeBytes(data);
  for (final file in archive) {
    final filename = p.join(destDir.path, file.name);
    if (file.isFile) {
      final outFile = await File(filename).create(recursive: true);
      await outFile.writeAsBytes(file.content);
    } else {
      await Directory(filename).create(recursive: true);
    }
  }

  debugPrint("Finished unpacking application archive.");
  return destDir.path;
}

Future<String> extractAssetZip(String assetPath, {String? targetPath}) async {
  return extractAssetOrFile(assetPath, targetPath: targetPath);
}

Future<String> extractFileZip(String filePath, {String? targetPath}) async {
  return extractAssetOrFile(filePath, isAsset: false, targetPath: targetPath);
}

Future<String> extractAsset(String assetPath) async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory documentsDir = await getApplicationDocumentsDirectory();

  // (re-)create destination directory
  Directory(p.join(documentsDir.path, p.dirname(assetPath)))
      .create(recursive: true);

  // extract file from assets
  var destPath = p.join(documentsDir.path, assetPath);
  if (kDebugMode && await File(destPath).exists()) {
    await File(destPath).delete();
  }
  ByteData data = await rootBundle.load(assetPath);
  List<int> bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await File(destPath).writeAsBytes(bytes);
  return destPath;
}
