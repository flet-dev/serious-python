import 'dart:io';
import 'package:path/path.dart' as path;

class FileSystem {
  static Future<String> findMainFile(String appPath) async {
    if (await File(path.join(appPath, "main.pyc")).exists()) {
      return path.join(appPath, "main.pyc");
    } else if (await File(path.join(appPath, "main.py")).exists()) {
      return path.join(appPath, "main.py");
    }
    throw Exception(
        "App archive must contain either `main.py` or `main.pyc`; otherwise `appFileName` must be specified.");
  }

  static Future<void> setCurrentDirectory(String path) async {
    Directory.current = path;
  }

  static bool get isWindows => Platform.isWindows;
}