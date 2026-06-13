import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// iOS / macOS implementation of [SeriousPythonPlatform].
///
/// Python lifecycle (env, sys.path, Py_Initialize, run, finalize, sync/async)
/// lives in `serious_python_run`, statically linked into the host app via
/// dart_bridge.xcframework. This class just resolves the python.bundle
/// resource path from the Swift plugin and dispatches a single FFI call.
class SeriousPythonDarwin extends SeriousPythonPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('serious_python');

  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonDarwin();
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    final resourcePath =
        await methodChannel.invokeMethod<String>('getResourcePath');
    if (resourcePath == null) {
      throw StateError(
          'serious_python: failed to resolve plugin resource path');
    }

    final appDir = p.dirname(appPath);
    final pythonPaths = <String>[
      ...?modulePaths,
      appDir,
      p.join(appDir, '__pypackages__'),
      p.join(resourcePath, 'site-packages'),
      p.join(resourcePath, 'stdlib'),
      p.join(resourcePath, 'stdlib', 'lib-dynload'),
    ];

    final env = <String, String>{
      'PYTHONINSPECT': '1',
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': resourcePath,
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
    if (rc != 0) {
      return 'Python exited with code $rc';
    }
    return null;
  }
}
