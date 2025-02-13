abstract class PlatformUtils {
  Future<String> extractAssetOrFile(String path,
      {bool isAsset = true, String? targetPath, bool checkHash = false});

  Future<String> extractAssetZip(String assetPath,
      {String? targetPath, bool checkHash = false});

  Future<String> extractFileZip(String filePath,
      {String? targetPath, bool checkHash = false});

  Future<String> extractAsset(String assetPath);

  Future<String> getDirFiles(String path, {bool recursive = false});
}