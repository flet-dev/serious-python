import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'src/serious_python_platform_interface.dart';
import 'src/utils.dart';

/// Provides cross-platform functionality for running Python programs.
class SeriousPython {
  SeriousPython._();

  /// Returns the current name and version of the operating system.
  static Future<String?> getPlatformVersion() {
    return SeriousPythonPlatform.instance.getPlatformVersion();
  }

  /// Runs Python program from an asset.
  ///
  /// [assetPath] is the path to an asset which is a zip archive
  /// with a Python program. When the app starts the archive is unpacked
  /// to a temporary directory and Serious Python plugin will try to run
  /// `main.py` in the root of the archive. Current directory is changed to
  /// a temporary directory.
  ///
  /// If a Python app has a different entry point
  /// it could be specified with [appFileName] parameter.
  ///
  /// Environment variables that must be available to a Python program could
  /// be passed in [environmentVariables].
  ///
  /// By default, Serious Python expects Python dependencies installed into
  /// `__pypackages__` directory in the root of app directory. Additional paths
  /// to look for 3rd-party packages can be specified with [modulePaths] parameter.
  ///
  /// Set [sync] to `true` to sychronously run Python program; otherwise the
  /// program starts in a new thread.
  static Future<String?> run(String assetPath,
      {String? appFileName,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    // unpack app
    WidgetsFlutterBinding.ensureInitialized();
    String appPath = "";
    if (p.extension(assetPath) == ".zip") {
      appPath = await extractAssetZip(assetPath);
      if (appFileName != null) {
        appPath = p.join(appPath, appFileName);
      } else if (await File(p.join(appPath, "main.pyc")).exists()) {
        appPath = p.join(appPath, "main.pyc");
      } else if (await File(p.join(appPath, "main.py")).exists()) {
        appPath = p.join(appPath, "main.py");
      } else {
        throw Exception(
            "App archive must contain either `main.py` or `main.pyc`; otherwise `appFileName` must be specified.");
      }
    } else {
      appPath = await extractAsset(assetPath);
    }

    // set current directory to app path
    Directory.current = p.dirname(appPath);

    // run python program
    return SeriousPythonPlatform.instance.run(appPath,
        modulePaths: modulePaths,
        environmentVariables: environmentVariables,
        sync: sync);
  }
}
