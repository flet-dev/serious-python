#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

// dart_bridge's C entry points (serious_python_run, DartBridge_*,
// serious_python_{is_mp_invocation,main}) used to need keep-alive references
// here: it shipped as a static archive linked into the host app executable,
// which exports nothing, so the dlsym lookups Dart (`DynamicLibrary.process()`)
// and the macOS host's main.swift perform could fail. dart_bridge now ships as a
// dynamic framework (embedded + signed) whose symbols are exported from its own
// loaded image, so no keep-alive is required — see dart-bridge 1.6.0.

/// Thin Flutter plugin: surfaces the python.bundle resource path to Dart.
/// All Python lifecycle now lives in `serious_python_run`
/// (dart_bridge.xcframework), invoked from Dart.
public class SeriousPythonPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Workaround for https://github.com/flutter/flutter/issues/118103.
        #if os(iOS)
            let messenger = registrar.messenger()
        #else
            let messenger = registrar.messenger
        #endif
        let channel = FlutterMethodChannel(name: "serious_python", binaryMessenger: messenger)
        let instance = SeriousPythonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getResourcePath":
            // Dart calls this to discover the stdlib / site-packages / app layout
            // before invoking `serious_python_run`. The two build systems put the
            // trees in different bundles:
            #if SWIFT_PACKAGE
                // SwiftPM: staged as `.copy` resources into Bundle.module, whose
                // resourcePath contains stdlib/ site-packages/ app/ directly.
                guard let resourcePath = Bundle.module.resourcePath else {
                    result(FlutterError(code: "PYTHON_BUNDLE_ERROR",
                                        message: "Failed to resolve Bundle.module resourcePath",
                                        details: nil))
                    return
                }
                result(resourcePath)
            #else
                // CocoaPods: the python.bundle that prepare_{ios,macos}.sh assembles
                // lives inside the plugin framework as a Resources subbundle.
                guard let frameworkBundle = Bundle(for: type(of: self)).resourceURL else {
                    result(FlutterError(code: "FRAMEWORK_BUNDLE_ERROR",
                                        message: "Failed to get framework resource URL",
                                        details: nil))
                    return
                }
                let pythonBundleURL = frameworkBundle.appendingPathComponent("python.bundle")
                guard let pythonBundle = Bundle(url: pythonBundleURL),
                      let resourcePath = pythonBundle.resourcePath else {
                    result(FlutterError(code: "PYTHON_BUNDLE_ERROR",
                                        message: "Failed to load python.bundle",
                                        details: pythonBundleURL.path))
                    return
                }
                result(resourcePath)
            #endif

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
