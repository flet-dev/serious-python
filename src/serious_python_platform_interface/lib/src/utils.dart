import 'dart:io';

/// Lists the files under [path] (optionally [recursive]ly), one per line.
///
/// Small debug helper used to inspect bundled/unpacked directories. Returns
/// `"<not found>"` if the directory does not exist.
Future<String> getDirFiles(String path, {bool recursive = false}) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    return "<not found>";
  }
  return (await dir.list(recursive: recursive).toList())
      .map((file) => file.path)
      .join('\n');
}
