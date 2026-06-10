import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// Windows implementation of [SeriousPythonPlatform].
///
/// Python lifecycle (env, sys.path, Py_Initialize, run, finalize, sync/async)
/// lives in `serious_python_run`, packaged as `dart_bridge.dll` (Release CRT)
/// or `dart_bridge_d.dll` (Debug CRT) and bundled next to the .exe by this
/// plugin's CMakeLists.txt. The correct DLL is picked at runtime based on
/// [kDebugMode].
///
/// This class derives PYTHONHOME from `Platform.resolvedExecutable` (the
/// runner .exe directory, where the bundled CPython lives) and dispatches a
/// single FFI call to `serious_python_run`.
class SeriousPythonWindows extends SeriousPythonPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python_windows');

  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonWindows();
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return '$version ${Platform.resolvedExecutable}';
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final appDir = p.dirname(appPath);

    final pythonPaths = <String>[
      ...?modulePaths,
      appDir,
      p.join(appDir, '__pypackages__'),
      p.join(exeDir, 'site-packages'),
      p.join(exeDir, 'DLLs'),
      p.join(exeDir, 'Lib'),
      p.join(exeDir, 'Lib', 'site-packages'),
    ];

    final env = <String, String>{
      'PYTHONINSPECT': '1',
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': exeDir,
      'PYTHONPATH': pythonPaths.join(';'),
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
}
