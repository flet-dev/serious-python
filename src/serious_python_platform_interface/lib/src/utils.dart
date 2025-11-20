import 'utils_web.dart' if (dart.library.io) 'utils_io.dart';

Future<String> extractAssetOrFile(String path,
    {bool isAsset = true, String? targetPath, bool checkHash = false}) {
  return getPlatformUtils().extractAssetOrFile(path,
      isAsset: isAsset, targetPath: targetPath, checkHash: checkHash);
}

Future<String> extractAssetZip(String assetPath,
    {String? targetPath, bool checkHash = false}) {
  return getPlatformUtils().extractAssetZip(assetPath,
      targetPath: targetPath, checkHash: checkHash);
}

Future<String> extractFileZip(String filePath,
    {String? targetPath, bool checkHash = false}) {
  return getPlatformUtils().extractFileZip(filePath,
      targetPath: targetPath, checkHash: checkHash);
}

Future<String> extractAsset(String assetPath) {
  return getPlatformUtils().extractAsset(assetPath);
}

Future<String> getDirFiles(String path, {bool recursive = false}) {
  return getPlatformUtils().getDirFiles(path, recursive: recursive);
}