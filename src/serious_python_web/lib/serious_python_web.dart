import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:serious_python_platform_interface/serious_python_platform_interface.dart';
import 'package:serious_python_web/pyodide.dart';

class SeriousPythonWeb extends SeriousPythonPlatform {
  bool _isInitialized = false;
  PyodideInterface? _pyodide;
  final Set<String> _loadedModules = {};

  final String pyodideVersion = 'v0.27.2';
  late final String pyodideBaseURL = 'https://cdn.jsdelivr.net/pyodide/$pyodideVersion/full/';
  late final String pyodideJS = '${pyodideBaseURL}pyodide.js';

  /// Registers this class as the default instance of [SeriousPythonPlatform]
  static void registerWith(Registrar registrar) {
    SeriousPythonPlatform.instance = SeriousPythonWeb();
  }

  @override
  Future<String?> getPlatformVersion() async {
    return 'web';
  }

  Future<List<String>> _parseRequirementsFile(String requirementsFile) async {
    try {
      final content = await rootBundle.loadString(requirementsFile);
      return content
          .split('\n')
          .map((line) => line.trim())
          .where((line) =>
      line.isNotEmpty &&
          !line.startsWith('#') &&
          !line.startsWith('-'))
          .map((line) => line.split('==')[0].split('>=')[0].trim())
          .toList();
    } catch (e) {
      print('Error parsing requirements.txt: $e');
      rethrow;
    }
  }

  Future<String> _getRequirementsFileFromAssets() async {
    // Load the asset manifest
    // TODO Optimize not to load twice
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);

    // Filter for Python files in the specified directory
    return manifest.keys.firstWhere((String key) => key.contains("requirements.txt"));
  }

  Future<void> _loadPyodidePackages() async {
    try {
      // Parse requirements.txt
      final requirementsFile = await _getRequirementsFileFromAssets();
      final packages = await _parseRequirementsFile(requirementsFile);

      if (packages.isEmpty) {
        print("No packages found in requirements.txt");
        return;
      }

      print("Loading Pyodide packages: ${packages.join(', ')}");

      for(final package in packages) {
        // Load packages
        try {
          await js_util.promiseToFuture(
              js_util.callMethod(_pyodide!, 'loadPackage', [package])
          );
        } catch(e) {
          print('Could not import package: $package');
        }
      }

      print("Packages loaded successfully");
    } catch (e) {
      print('Error loading packages: $e');
      rethrow;
    }
  }

  Future<void> _initializePyodide() async {
    if (_pyodide != null) return;

    try {
      // Inject required meta tags first
      _injectMetaTags();

      // Create and add the script element
      final scriptElement = html.ScriptElement()
        ..src = pyodideJS
        ..type = 'text/javascript';

      html.document.head!.append(scriptElement);

      // Wait for script to load
      await _waitForPyodide();

      // Initialize Pyodide with correct base URL
      final config = js_util.jsify({
        'indexURL': pyodideBaseURL,
        'stdout': (String s) => print('Python stdout: $s'),
        'stderr': (String s) => print('Python stderr: $s')
      });

      final pyodidePromise = loadPyodide(config);
      _pyodide = await js_util.promiseToFuture<PyodideInterface>(pyodidePromise);

      // Test Python initialization
      await _runPythonCode("""
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
    var attempts = 0;
    while (attempts < 100) {
      if (js_util.hasProperty(js_util.globalThis, 'loadPyodide')) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    throw Exception('Timeout waiting for Pyodide to load');
  }

  static void _injectMetaTags() {
    try {
      final head = html.document.head;

      // Check if meta tags already exist
      if (!head!.querySelectorAll('meta[name="cross-origin-opener-policy"]').isNotEmpty) {
        final coopMeta = html.MetaElement()
          ..name = 'cross-origin-opener-policy'
          ..content = 'same-origin';
        head.append(coopMeta);
      }

      if (!head.querySelectorAll('meta[name="cross-origin-embedder-policy"]').isNotEmpty) {
        final coepMeta = html.MetaElement()
          ..name = 'cross-origin-embedder-policy'
          ..content = 'require-corp';
        head.append(coepMeta);
      }
    } catch (e) {
      print('Error injecting meta tags: $e');
    }
  }

  Future<List<String>> _listPythonFilesInDirectory(String directory) async {
    // Load the asset manifest
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);

    // Filter for Python files in the specified directory
    return manifest.keys.where((String key) => key.contains(directory) && key.endsWith('.py')).toList();
  }

  Future<void> _loadModules(String moduleName, List<String> modulePaths) async {
    // Create a package directory in Pyodide's virtual filesystem
    await _runPythonCode('''
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
      await _pyodide!.FS.writeFile('/package/$moduleName/$fileName', moduleCode, {'encoding': 'utf8'});
    }
  }

  Future<void> _loadModuleDirectories(List<String> modulePaths) async {
    final List<String> moduleNamesToImport = [];
    for(final directory in modulePaths) {
      final moduleName = directory.split("/").last;
      if(_loadedModules.contains(moduleName)) {
        continue;
      }

      final pythonFiles = await _listPythonFilesInDirectory(directory);
      await _loadModules(moduleName, pythonFiles);
      _loadedModules.add(moduleName);
      moduleNamesToImport.add(moduleName);
    }
    // Import the modules using pyimport
    for(final moduleNameToImport in moduleNamesToImport) {
      await _pyodide!.pyimport('$moduleNameToImport');
    }
  }

  Future<void> ensureInitialized(String appPath) async {
    if (!_isInitialized) {
      // TODO REQUIREMENTS FILE PATH: ARGUMENT?
      await _initializePyodide();
      await _loadPyodidePackages();
      _isInitialized = true;
    }
  }

  @override
  Future<String?> run(String appPath,
      {String? script, List<String>? modulePaths, Map<String, String>? environmentVariables, bool? sync}) async {
    try {
      await ensureInitialized(appPath);

      // Load the Python code from the asset
      final pythonCode = await rootBundle.loadString(appPath);

      // Set environment variables if provided
      if (environmentVariables != null) {
        print("Running python web command with environment variables: $environmentVariables");

        await _runPythonCode('''
import os
${environmentVariables.entries.map((e) => "os.environ['${e.key}'] = '${e.value}'").join('\n')}
''');
      }

      // Add module paths if provided
      if (modulePaths != null) {
        int oldNModules = _loadedModules.length;
        await _loadModuleDirectories(modulePaths);
        int newNModules = _loadedModules.length;
        print("Loaded ${newNModules - oldNModules} new modules!");
      }

//      final String debugCode = '''
//import os
//import sys
//
//print("Python version:", sys.version)
//print("Python path:", sys.path)
//print("Current working directory:", os.getcwd())
//print("Directory contents:", os.listdir('/package'))
//''';

      await _runPythonCode(pythonCode);

      final result = _pyodide!.globals.get("pyodide_result");
      return result.toString();
    } catch (e) {
      print('Error running Python code: $e');
      return 'Error: $e';
    }
  }

  Future<void> _runPythonCode(String code) async {
    try {
      // print("Running Python code: \n$code");
      final promise = _pyodide!.runPythonAsync(code);
      await js_util.promiseToFuture(promise);
    } catch (e) {
      print('Error running Python code: $e');
      rethrow;
    }
  }

  @override
  void terminate() {
    // No need to implement for web
  }
}
