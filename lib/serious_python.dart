import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'src/serious_python_platform_interface.dart';
import 'src/utils.dart';

class SeriousPython {
  Future<String?> getPlatformVersion() {
    return SeriousPythonPlatform.instance.getPlatformVersion();
  }

  Future<String?> run(String assetPath,
      {String? appFileName,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    WidgetsFlutterBinding.ensureInitialized();
    String appPath = "";
    if (p.extension(assetPath) == ".zip") {
      appPath = await extractAssetZip(assetPath);
      if (appFileName != null) {
        appPath = p.join(appPath, appFileName);
      } else if (await File(p.join(appPath, "main.py")).exists()) {
        appPath = p.join(appPath, "main.py");
      } else {
        throw Exception(
            "App archive must contain either `main.py` or `main.pyc`; otherwise `appFileName` must be specified.");
      }
    } else {
      appPath = await extractAsset(assetPath);
    }
    return SeriousPythonPlatform.instance.run(appPath,
        modulePaths: modulePaths,
        environmentVariables: environmentVariables,
        sync: sync);
  }
}
