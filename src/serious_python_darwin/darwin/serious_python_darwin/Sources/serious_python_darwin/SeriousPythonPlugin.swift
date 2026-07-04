#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

// Keep-alive references to dart_bridge.xcframework's C entry points. Dart
// resolves them via `DynamicLibrary.process()` at runtime; without these
// static references the host app's linker `-dead_strip` pass could drop
// them even though `-all_load` pulled the archive members in.
@_silgen_name("serious_python_run")
private func _sp_run_keepalive(_ cfg: OpaquePointer?) -> Int32
@_silgen_name("DartBridge_InitDartApiDL")
private func _sp_init_keepalive(_ data: UnsafeMutableRawPointer?) -> Int
@_silgen_name("DartBridge_EnqueueMessage")
private func _sp_enqueue_keepalive(_ data: UnsafePointer<CChar>?, _ len: Int)
// multiprocessing child-interception entry points (dart_bridge >= 1.5.0),
// dlsym'd by the host app's main.swift before NSApplicationMain.
@_silgen_name("serious_python_is_mp_invocation")
private func _sp_is_mp_keepalive(
  _ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32
@_silgen_name("serious_python_main")
private func _sp_main_keepalive(
  _ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

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

        // Static reference to dart_bridge symbols — see top-of-file note.
        // The branch is unreachable at runtime (the registrar argument is
        // always non-nil), but the linker only sees a live call site.
        if unsafeBitCast(registrar, to: Int.self) == 0 {
            _ = _sp_run_keepalive(nil)
            _ = _sp_init_keepalive(nil)
            _sp_enqueue_keepalive(nil, 0)
            _ = _sp_is_mp_keepalive(0, nil)
            _ = _sp_main_keepalive(0, nil)
        }
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
