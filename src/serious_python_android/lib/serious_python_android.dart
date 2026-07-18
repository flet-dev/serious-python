import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// Android implementation of [SeriousPythonPlatform].
///
/// Python lifecycle (env, sys.path, Py_Initialize, run, finalize, sync/async)
/// lives in `serious_python_run`, packaged as `libdart_bridge.so` and bundled
/// into the APK by the plugin's gradle pipeline (see `android/build.gradle`'s
/// `downloadDartBridge_<abi>` tasks).
///
/// This class:
/// 1. In [prepareApp], copies the stored asset zips (stdlib / sitepackages /
///    extract / app) out of the APK into the app-support directory once
///    (version-keyed), since CPython can't import from inside the .apk and the
///    app payload must live on a writable path.
/// 2. In [run], builds env vars + sys.path entries (pointing at those copied
///    zips) and hands them to `serious_python_run` in a single FFI call.
class SeriousPythonAndroid extends SeriousPythonPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('android_plugin');

  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonAndroid();
  }

  /// The serious_python/flet-owned storage namespace: `<support>/flet`, where
  /// `<support>` is `getApplicationSupportDirectory()` (== `context.getFilesDir()`
  /// on Android). Holds `{app, stdlib.zip, sitepackages.zip, extract/, .key}`.
  /// The sibling `<support>/data` (user data / cwd) is never touched here.
  Future<String> _base() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'flet');
  }

  @override
  Future<String> prepareApp() async {
    final base = await _base();
    final appDir = p.join(base, 'app');
    final stdlibZip = p.join(base, 'stdlib.zip');
    final siteZip = p.join(base, 'sitepackages.zip');
    final extractDir = p.join(base, 'extract');

    // `getAppVersion` returns `versionName+versionCode+lastUpdateTime`, so the
    // key changes on every (re)install — including `flet debug`'s repeated
    // same-version `flutter run` reinstalls — while staying stable across plain
    // relaunches. Keeping only versionName+versionCode here would make the
    // debug workflow keep running previously-unpacked, stale app code.
    final appVersion = await _appVersion();
    final key = appVersion != null ? 'app:$appVersion' : 'app:dev';
    final marker = File(p.join(base, '.key'));
    final upToDate =
        await marker.exists() && (await marker.readAsString()) == key;
    if (!upToDate) {
      await Directory(base).create(recursive: true);
      // Re-materialize the unpacked trees; leave the sibling `<support>/data`
      // (user data) alone — it must survive app updates.
      for (final dir in [appDir, extractDir]) {
        if (await Directory(dir).exists()) {
          await Directory(dir).delete(recursive: true);
        }
      }
      // Pure-code zips imported in place via zipimport (streamed whole to disk).
      await methodChannel.invokeMethod(
          'extractAsset', {'asset': 'stdlib.zip', 'dest': stdlibZip});
      await methodChannel.invokeMethod(
          'extractAsset', {'asset': 'sitepackages.zip', 'dest': siteZip});
      // Path-hungry packages + the app payload are unpacked to disk.
      await methodChannel.invokeMethod(
          'unzipAsset', {'asset': 'extract.zip', 'dest': extractDir});
      await methodChannel
          .invokeMethod('unzipAsset', {'asset': 'app.zip', 'dest': appDir});
      await marker.writeAsString(key);
    }

    return appDir;
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    // [prepareApp] has already materialized everything; recompute the paths
    // (deterministic from the support dir) — no unpacking here.
    final base = await _base();
    final stdlibZip = p.join(base, 'stdlib.zip');
    final siteZip = p.join(base, 'sitepackages.zip');
    final extractDir = p.join(base, 'extract');

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

    // pyjnius support: load its JNI helper (libpyjni.so, from the flet-libpyjni
    // dependency) via Java's `System.loadLibrary`, which runs its JNI_OnLoad —
    // capturing the JavaVM + app ClassLoader that pyjnius's `PyJni_*` calls rely
    // on. `dart:ffi`'s dlopen (used for libdart_bridge) never triggers
    // JNI_OnLoad, so this Java-side load must happen before the interpreter
    // imports `jnius`. Best-effort: a no-op (UnsatisfiedLinkError) for apps that
    // don't depend on pyjnius, since libpyjni.so isn't bundled then.
    var jniReady = false;
    try {
      await methodChannel.invokeMethod('loadLibrary', {'libname': 'pyjni'});
      jniReady = true;
    } catch (_) {
      // pyjnius not in use (or libpyjni.so absent) — nothing to do.
    }

    final env = <String, String>{
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': base,
      'PYTHONPATH': pythonPaths.join(':'),
      if (jniReady) 'FLET_JNI_READY': '1',
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
