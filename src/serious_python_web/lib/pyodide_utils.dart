import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/services.dart';
import 'package:serious_python_web/pyodide_interop.dart';

class PyodideUtils {
  static void injectMetaTags() {
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

  static Future<Set<String>> getRequirementsFilesFromAssets() async {
    // Load the asset manifest
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);

    // Filter for Python files in the specified directory
    return manifest.keys.where((String key) => key.contains("requirements.txt")).toSet();
  }

  static Future<List<String>> parseRequirementsFiles(Set<String> requirementsFiles) async {
    try {
      final List<String> requirements = [];
      for(final requirementsFile in requirementsFiles) {
        final content = await rootBundle.loadString(requirementsFile);
        final parsedRequirements = content
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#') && !line.startsWith('-'))
            .map((line) => line.split('==')[0].split('>=')[0].trim())
            .toList();
        requirements.addAll(parsedRequirements);
      }
      return requirements;
    } catch (e) {
      print('Error parsing requirements.txt: $e');
      rethrow;
    }
  }

  static Future<List<String>> listPythonFilesInDirectory(String directory) async {
    // Load the asset manifest
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);

    // Filter for Python files in the specified directory
    return manifest.keys.where((String key) => key.contains(directory) && key.endsWith('.py')).toList();
  }

  static Future<void> setupEnvironmentVariables(
      PyodideInterface? pyodide, Map<String, String>? environmentVariables) async {
    if (environmentVariables == null) {
      return;
    }
    print("Running python web command with environment variables: $environmentVariables");

    await runPythonCode(pyodide, '''
import os
${environmentVariables.entries.map((e) => "os.environ['${e.key}'] = '${e.value}'").join('\n')}
''');
  }

  static Future<void> printPythonDebug(PyodideInterface? pyodide) async {
    final String debugCode = '''
import os
import sys

print("Python version:", sys.version)
print("Python path:", sys.path)
print("Current working directory:", os.getcwd())
print("Directory contents:", os.listdir('/package'))
''';
    await runPythonCode(pyodide, debugCode);
  }

  static Future<void> runPythonCode(PyodideInterface? pyodide, String code) async {
    try {
      if (pyodide == null) {
        throw Exception("Trying to run python code on non-existing pyodide object!");
      }
      final promise = pyodide.runPythonAsync(code);
      await js_util.promiseToFuture(promise);
    } catch (e) {
      print('Error running Python code: $e');
      rethrow;
    }
  }

  static Future<String> getPyodideResult(PyodideInterface? pyodide) async {
    try {
      if (pyodide == null) {
        throw Exception("Trying to get pyodide result on non-existing pyodide object!");
      }
      final result = pyodide.globals.get("pyodide_result");
      return result.toString();
    } catch (e) {
      print('Error getting pyodide result: $e');
      rethrow;
    }
  }
}
