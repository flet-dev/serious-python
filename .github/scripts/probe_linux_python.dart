import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serious_python_platform_interface/src/dart_bridge_ffi.dart';

// Run against the installed bundle without Flutter's handling of native stderr.
// Like the app, this loads CPython through dart:ffi, rather than starting a
// Python executable (which would expose its symbols globally).
void main(List<String> args) {
  final bundle = p.absolute(args.single);
  final stdlib = Directory(bundle)
      .listSync()
      .whereType<Directory>()
      .singleWhere((d) => RegExp(r'^python3\.\d+$').hasMatch(p.basename(d.path)))
      .path;
  final paths = [p.join(bundle, 'site-packages'), stdlib];
  final bridge = DartBridge.open(p.join(bundle, 'lib', 'libdart_bridge.so'));
  final result = runPython(
    bridge: bridge,
    script: '''
import sys
print("Bundled Python:", sys.version, flush=True)
print("Module paths:", sys.path, flush=True)
from pydantic import BaseModel
class Probe(BaseModel):
    value: int
assert Probe.model_validate({"value": "42"}).value == 42
print("Pydantic validation passed", flush=True)
''',
    modulePaths: paths,
    environmentVariables: {
      'PYTHONHOME': bundle,
      'PYTHONPATH': paths.join(':'),
      'PYTHONUNBUFFERED': '1',
      'PYTHONNOUSERSITE': '1',
    },
    sync: true,
  );
  exit(result);
}
