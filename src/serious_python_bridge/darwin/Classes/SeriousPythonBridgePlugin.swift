#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

import Python
import serious_python_darwin

public class SeriousPythonBridgePlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register dart_bridge as a built-in CPython module so `import
        // dart_bridge` resolves against the statically linked symbols in
        // ../native/dart_bridge.c instead of looking for a filesystem .so.
        // Required on iOS (no late-loaded dylibs allowed). Used on macOS too
        // for symbol-visibility consistency: Dart's DynamicLibrary.process()
        // and Python's `import dart_bridge` then share the same
        // global_enqueue_handler_func state.
        SeriousPythonPlugin.registerPythonExtension(
            name: "dart_bridge",
            initFn: PyInit_dart_bridge
        )
    }
}
