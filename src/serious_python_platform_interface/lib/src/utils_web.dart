import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'utils_interface.dart';

class WebUtils implements PlatformUtils {
  @override
  Future<String> extractAssetOrFile(String path,
      {bool isAsset = true, String? targetPath, bool checkHash = false}) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (isAsset) {
        await rootBundle.load(path);
      }
      return path;
    } catch (e) {
      debugPrint('Error handling web asset: $e');
      rethrow;
    }
  }

  @override
  Future<String> extractAssetZip(String assetPath,
      {String? targetPath, bool checkHash = false}) {
    return extractAssetOrFile(assetPath,
        targetPath: targetPath, checkHash: checkHash);
  }

  @override
  Future<String> extractFileZip(String filePath,
      {String? targetPath, bool checkHash = false}) {
    return extractAssetOrFile(filePath,
        isAsset: false, targetPath: targetPath, checkHash: checkHash);
  }

  @override
  Future<String> extractAsset(String assetPath) async {
    WidgetsFlutterBinding.ensureInitialized();
    await rootBundle.load(assetPath);
    return assetPath;
  }

  @override
  Future<String> getDirFiles(String path, {bool recursive = false}) async {
    return path;
  }
}

PlatformUtils getPlatformUtils() => WebUtils();