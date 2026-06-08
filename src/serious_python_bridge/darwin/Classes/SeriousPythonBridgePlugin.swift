#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

import Darwin
import serious_python_darwin

public class SeriousPythonBridgePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register dart_bridge as a built-in CPython module so `import
        // dart_bridge` resolves against the statically linked symbols in
        // ../native/dart_bridge.c instead of looking for a filesystem .so.
        // Required on iOS (no late-loaded dylibs allowed). Used on macOS too
        // for symbol-visibility consistency: Dart's DynamicLibrary.process()
        // and Python's `import dart_bridge` share the same
        // global_enqueue_handler_func state.
        //
        // dlsym(RTLD_DEFAULT) finds PyInit_dart_bridge in the process's global
        // symbol table — populated by linking dart_bridge.c into this pod. We
        // avoid declaring the symbol in a header because doing so pulls
        // <Python.h> into the umbrella module map, which CocoaPods scans
        // without the Python.framework search path.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "PyInit_dart_bridge") else {
            NSLog("[SeriousPythonBridgePlugin] PyInit_dart_bridge symbol not found in process")
            return
        }
        let initFn = unsafeBitCast(symbol, to: SeriousPythonPlugin.PyInitFunction.self)
        SeriousPythonPlugin.registerPythonExtension(name: "dart_bridge", initFn: initFn)
    }
}
