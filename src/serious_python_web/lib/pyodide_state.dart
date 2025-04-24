import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/services.dart';
import 'package:serious_python_web/pyodide_constants.dart';
import 'package:serious_python_web/pyodide_interop.dart';
import 'package:serious_python_web/pyodide_utils.dart';


class PyodideStateManager {
  PyodideStateInitialize? _initState;
  PyodideStateLoadDependencies? _depState;
  PyodideStateLoadModuleCode? _moduleState;

  Future<PyodideInterface> getPyodide(List<String> modulePaths) async {
    if(_initState == null) {
      _initState = await PyodideStateInitialize().doSetup();
    }
    if(_depState == null) {
      _depState = await PyodideStateLoadDependencies(_initState!._pyodide!).doSetup();
    }
    if(_moduleState == null) {
      _moduleState = await PyodideStateLoadModuleCode(_depState!._pyodide);
    }
    _moduleState = await _moduleState!.doSetup(modulePaths);
    return _moduleState!._pyodide;
  }

}

class PyodideStateInitialize {
  PyodideInterface? _pyodide;

  Future<void> _initializePyodide() async {
    if (_pyodide != null) return;

    try {
      // Inject required meta tags first
      PyodideUtils.injectMetaTags();

      // Create and add the script element
      final scriptElement = html.ScriptElement()
        ..src = PyodideConstants.pyodideJS
        ..type = 'text/javascript';

      html.document.head!.append(scriptElement);

      // Wait for script to load
      await _waitForPyodide();

      // Initialize Pyodide with correct base URL
      final config = js_util.jsify({
        'indexURL': PyodideConstants.pyodideBaseURL,
        'stdout': (String s) => print('Python stdout: $s'),
        'stderr': (String s) => print('Python stderr: $s')
      });

      final pyodidePromise = loadPyodide(config);
      _pyodide = await js_util.promiseToFuture<PyodideInterface>(pyodidePromise);

      // Test Python initialization
      await PyodideUtils.runPythonCode(_pyodide, """
import sys
print(f"Python version: {sys.version}")
      """);

      print("Pyodide initialized successfully");
    } catch (e, stackTrace) {
      print('Error initializing Pyodide: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _waitForPyodide() async {
    for (int attempts = 0; attempts < 100; attempts++) {
      if (js_util.hasProperty(js_util.globalThis, 'loadPyodide')) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw Exception('Timeout waiting for Pyodide to load');
  }

  Future<PyodideStateInitialize> doSetup() async {
    try {
      await _initializePyodide();
      return this;
    } catch (e) {
      rethrow;
    }
  }
}

class PyodideStateLoadDependencies {
  final PyodideInterface _pyodide;

  PyodideStateLoadDependencies(this._pyodide);

  Future<void> _loadPythonDependencies() async {
    try {
      // Parse requirements.txt
      final requirementsFile = await PyodideUtils.getRequirementsFilesFromAssets();
      final packages = await PyodideUtils.parseRequirementsFiles(requirementsFile);

      if (packages.isEmpty) {
        print("Nothing to do: No packages found in all requirements.txt files.");
        return;
      }

      print("Loading Pyodide packages: ${packages.join(', ')}");
      for (final package in packages) {
        try {
          await js_util.promiseToFuture(js_util.callMethod(_pyodide, 'loadPackage', [package]));
        } catch (e) {
          print('Could not import package: $package');
        }
      }

      print("Packages loaded successfully");
    } catch (e) {
      print('Error loading packages: $e');
      rethrow;
    }
  }

  Future<PyodideStateLoadDependencies> doSetup() async {
    try {
      await _loadPythonDependencies();
      return this;
    } catch (e) {
      rethrow;
    }
  }
}

class PyodideStateLoadModuleCode {
  final PyodideInterface _pyodide;

  final Set<String> _loadedModules = {};

  PyodideStateLoadModuleCode(this._pyodide);

  Future<void> _loadModules(String moduleName, List<String> modulePaths) async {
    // Create a package directory in Pyodide's virtual filesystem
    await PyodideUtils.runPythonCode(_pyodide, '''
import os
import sys

if not os.path.exists('/package'):
    os.makedirs('/package')

if not os.path.exists('/package/$moduleName'):
    os.makedirs('/package/$moduleName')
    
# Create __init__.py to make it a package
with open(f'/package/$moduleName/__init__.py', 'w') as f:
    f.write('')
    
if '/package' not in sys.path:
    sys.path.append('/package')
''');

    for (final modulePath in modulePaths) {
      final moduleCode = await rootBundle.loadString(modulePath);
      final fileName = modulePath.split('/').last;

      // Use Pyodide's filesystem API to write module Code
      await _pyodide.FS.writeFile('/package/$moduleName/$fileName', moduleCode, {'encoding': 'utf8'});
    }
  }

  /// Loads all necessary python code modules and imports them via pyodide
  Future<void> _loadModuleDirectories(List<String> modulePaths) async {
    final List<String> moduleNamesToImport = [];
    for (final directory in modulePaths) {
      final moduleName = directory.split("/").last;
      if (_loadedModules.contains(moduleName)) {
        continue;
      }

      final pythonFiles = await PyodideUtils.listPythonFilesInDirectory(directory);
      await _loadModules(moduleName, pythonFiles);
      _loadedModules.add(moduleName);
      moduleNamesToImport.add(moduleName);
    }
    // Import the modules using pyimport
    for (final moduleNameToImport in moduleNamesToImport) {
      await _pyodide.pyimport('$moduleNameToImport');
    }
  }

  Future<PyodideStateLoadModuleCode> doSetup(List<String> modulePaths) async {
    try {
      await _loadModuleDirectories(modulePaths);
      return this;
    } catch(e) {
      rethrow;
    }
  }
}
