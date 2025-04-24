import 'package:js/js.dart';

// Define the external JavaScript functions we need
@JS('loadPyodide')
external Object loadPyodide(Object config);

@JS()
@anonymous
class PyodideInterface {
  external Object runPythonAsync(String code);
  external Object runPython(String code);
  external Object pyimport(String packageName);
  external FileSystem get FS;
  external PyodideGlobals get globals;
}

@JS()
@anonymous
class PyodideGlobals {
  external Object get(String name);
}

@JS()
@anonymous
class FileSystem {
  external Object writeFile(String path, String data, Object options);
}