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
  Future<String?> getPlatformVersion() =>
      methodChannel.invokeMethod<String>('getPlatformVersion');

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    final nativeLibraryDir =
        await methodChannel.invokeMethod<String>('getNativeLibraryDir');
    if (nativeLibraryDir == null) {
      throw StateError(
          'serious_python: failed to resolve native library dir');
    }

    final bundlePath = '$nativeLibraryDir/libpythonbundle.so';
    if (!await File(bundlePath).exists()) {
      throw Exception('Python bundle not found: $bundlePath');
    }

    final appVersion = await _appVersion();
    final invalidateKey = appVersion != null ? 'app:$appVersion' : null;

    final pythonLibPath = await extractFileZip(bundlePath,
        targetPath: 'python_bundle', invalidateKey: invalidateKey);

    final sitePackagesZip = '$nativeLibraryDir/libpythonsitepackages.so';
    String? sitePackagesPath;
    if (await File(sitePackagesZip).exists()) {
      sitePackagesPath = await extractFileZip(sitePackagesZip,
          targetPath: 'python_site_packages', invalidateKey: invalidateKey);
    }

    final programDir = p.dirname(appPath);
    final pythonPaths = <String>[
      ...?modulePaths,
      programDir,
      '$pythonLibPath/modules',
      '$pythonLibPath/stdlib',
      if (sitePackagesPath != null) sitePackagesPath,
    ];

    final env = <String, String>{
      'PYTHONINSPECT': '1',
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': pythonLibPath,
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
