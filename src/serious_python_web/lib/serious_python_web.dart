import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';
import 'package:serious_python_web/pyodide_state.dart';
import 'package:serious_python_web/pyodide_utils.dart';

class SeriousPythonWeb extends SeriousPythonPlatform {
  final PyodideStateManager _pyodideStateManager = PyodideStateManager();

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith(Registrar registrar) {
    SeriousPythonPlatform.instance = SeriousPythonWeb();
  }

  @override
  Future<String?> getPlatformVersion() async {
    return 'web';
  }

  @override
  Future<String?> run(String appPath,
      {String? script, List<String>? modulePaths, Map<String, String>? environmentVariables, bool? sync}) async {
    try {
      final pyodide = await _pyodideStateManager.getPyodide(modulePaths ?? []);

      // Load the Python code from the asset
      final pythonCode = await rootBundle.loadString(appPath);

      // Set environment variables if provided
      await PyodideUtils.setupEnvironmentVariables(pyodide, environmentVariables);

      // Print debug code in debug mode
      if(kDebugMode) {
        await PyodideUtils.printPythonDebug(pyodide);
      }

      // Run actual code
      await PyodideUtils.runPythonCode(pyodide, pythonCode);

      final result = await PyodideUtils.getPyodideResult(pyodide);
      return result;
    } catch (e) {
      print('Error running Pyodide: $e');
      return null;
    }
  }

  @override
  void terminate() {
    // No need to implement for web
  }
}
