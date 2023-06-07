import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> extractAssetZip(String assetPath) async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final destDir = Directory(p.join(documentsDir.path, p.dirname(assetPath)));

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

  // unpack from asset
  debugPrint("Start unpacking app archive");
  final bytes = await rootBundle.load(assetPath);
  final archive = ZipDecoder().decodeBytes(bytes.buffer.asUint8List());
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

Future<String> extractAsset(String assetPath) async {
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
