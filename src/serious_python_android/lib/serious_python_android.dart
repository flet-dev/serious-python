import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// Android implementation of [SeriousPythonPlatform].
///
/// Python lifecycle (env, sys.path, Py_Initialize, run, finalize, sync/async)
/// lives in `serious_python_run`, packaged as `libdart_bridge.so` and bundled
/// into the APK by the plugin's gradle pipeline (see `android/build.gradle`'s
/// `downloadDartBridge_<abi>` tasks).
///
/// This class:
/// 1. Pulls the python.bundle (zipped stdlib + dynload .so files) out of the
///    APK's nativeLibraryDir into a writable app-support directory, since
///    CPython can't import from inside the .apk.
/// 2. Builds env vars + sys.path entries and hands them to `serious_python_run`
///    in a single FFI call.
class SeriousPythonAndroid extends SeriousPythonPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('android_plugin');

  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonAndroid();
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    // Native extension modules now live in jniLibs (loaded by basename via the
    // finder); pure code ships in stored Android-asset zips. Copy the zips to disk
    // once (version-keyed) and unpack the allowlist payload; PYTHONPATH points at
    // the zips so zipimport serves pure modules in place.
    final filesDir = await methodChannel.invokeMethod<String>('getFilesDir');
    if (filesDir == null) {
      throw StateError('serious_python: failed to resolve files dir');
    }
    final base = p.join(filesDir, 'flet', 'py');
    final stdlibZip = p.join(base, 'stdlib.zip');
    final siteZip = p.join(base, 'sitepackages.zip');
    final extractDir = p.join(base, 'extract');

    final appVersion = await _appVersion();
    final key = appVersion != null ? 'app:$appVersion' : 'app:dev';
    final marker = File(p.join(base, '.key'));
    final upToDate =
        await marker.exists() && (await marker.readAsString()) == key;
    if (!upToDate) {
      await Directory(base).create(recursive: true);
      if (await Directory(extractDir).exists()) {
        await Directory(extractDir).delete(recursive: true);
      }
      await methodChannel.invokeMethod(
          'extractAsset', {'asset': 'stdlib.zip', 'dest': stdlibZip});
      await methodChannel.invokeMethod(
          'extractAsset', {'asset': 'sitepackages.zip', 'dest': siteZip});
      await methodChannel.invokeMethod(
          'unzipAsset', {'asset': 'extract.zip', 'dest': extractDir});
      await marker.writeAsString(key);
    }

    final programDir = p.dirname(appPath);
    // Highest -> lowest precedence. site-packages before stdlib so pip backports
    // can override; extract-dir before sitepackages.zip. Natives resolve via the
    // finder, not a sys.path entry.
    final pythonPaths = <String>[
      ...?modulePaths,
      programDir,
      extractDir,
      siteZip,
      stdlibZip,
    ];

    final env = <String, String>{
      'PYTHONINSPECT': '1',
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': base,
      'PYTHONPATH': pythonPaths.join(':'),
      ...?environmentVariables,
    };

    final rc = runPython(
      bridge: DartBridge.instance,
      appPath: script == null ? appPath : null,
      script: script,
      modulePaths: pythonPaths,
      environmentVariables: env,
      sync: sync ?? false,
    );

    // sync=true: rc is the Python exit code. sync=false: rc is the spawn
    // result (0 = worker thread started successfully).
    return rc != 0 ? 'Python exited with code $rc' : null;
  }

  Future<String?> _appVersion() async {
    try {
      return await methodChannel.invokeMethod<String>('getAppVersion');
    } catch (_) {
      return null;
    }
  }
}
