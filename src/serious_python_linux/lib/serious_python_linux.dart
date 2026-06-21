import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';

/// Linux implementation of [SeriousPythonPlatform].
///
/// Python lifecycle (env, sys.path, Py_Initialize, run, finalize, sync/async)
/// lives in `serious_python_run`, packaged as `libdart_bridge.so` and
/// downloaded by the plugin's CMakeLists.txt from
/// flet-dev/dart-bridge's GitHub Releases.
///
/// At runtime this class:
/// 1. Derives PYTHONHOME from `Platform.resolvedExecutable` (where the
///    bundled CPython stdlib lives, alongside the runner .exe).
/// 2. Locates the `python3.<minor>` stdlib subdir by scanning the exe dir
///    (the actual minor version is fixed at build time but the Dart side
///    doesn't have a compile-time constant for it).
/// 3. Hands env + sys.path to `serious_python_run` in a single FFI call.
class SeriousPythonLinux extends SeriousPythonPlatform {
  static void registerWith() {
    SeriousPythonPlatform.instance = SeriousPythonLinux();
  }

  /// The app ships unpacked inside the bundle at `<exeDir>/app` (placed by the
  /// Linux CMakeLists, next to the `python3.<minor>` stdlib + `site-packages`).
  @override
  Future<String> prepareApp() async {
    return p.join(p.dirname(Platform.resolvedExecutable), 'app');
  }

  @override
  Future<String?> run(String appPath,
      {String? script,
      List<String>? modulePaths,
      Map<String, String>? environmentVariables,
      bool? sync}) async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final appDir = p.dirname(appPath);
    final stdlibDir = _resolvePythonStdlibDir(exeDir);

    final pythonPaths = <String>[
      ...?modulePaths,
      appDir,
      p.join(appDir, '__pypackages__'),
      p.join(exeDir, 'site-packages'),
      stdlibDir,
    ];

    final env = <String, String>{
      'PYTHONINSPECT': '1',
      'PYTHONDONTWRITEBYTECODE': '1',
      'PYTHONNOUSERSITE': '1',
      'PYTHONUNBUFFERED': '1',
      'LC_CTYPE': 'UTF-8',
      'PYTHONHOME': exeDir,
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

  /// The Linux CMakeLists installs the python stdlib at
  /// `<exeDir>/python<X.Y>`. Find the right subdir by name pattern.
  static String _resolvePythonStdlibDir(String exeDir) {
    final pattern = RegExp(r'^python3\.\d+$');
    final match = Directory(exeDir).listSync().whereType<Directory>().firstWhere(
          (d) => pattern.hasMatch(p.basename(d.path)),
          orElse: () => throw StateError(
              'serious_python: no python3.<minor> stdlib dir found under $exeDir'),
        );
    return match.path;
  }
}
