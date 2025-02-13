// Stub implementation for web
class FileSystem {
  static Future<String> findMainFile(String appPath) async {
    return '$appPath/main.py';
  }

  static Future<void> setCurrentDirectory(String path) async {
    // No-op for web
  }

  static bool get isWindows => false;
}