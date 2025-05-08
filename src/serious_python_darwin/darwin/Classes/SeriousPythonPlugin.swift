#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

import Python

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
            case "getDartBridgePath":
                if let path = getDartBridgeLibraryPath() {
                    result(path)
                } else {
                    result(FlutterError(code: "DART_BRIDGE_LIB_NOT_FOUND",
                                        message: "Failed to locate dart_bridge library",
                                        details: nil))
                }
            case "getPythonModulePaths":
                if let paths = getPythonModulePaths() {
                    result(paths)
                } else {
                    result(FlutterError(code: "PYTHON_MODULE_PATHS_ERROR",
                                        message: "Failed to determine Python module paths",
                                        details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
        }
    }

  private func getPythonBundlePath() -> String? {
    guard let frameworkBundle = Bundle(for: Self.self).resourceURL else {
      return nil
    }
    let pythonBundleURL = frameworkBundle.appendingPathComponent("python.bundle")
    guard let pythonBundle = Bundle(url: pythonBundleURL),
          let resourcePath = pythonBundle.resourcePath else {
      return nil
    }
    return resourcePath
  }

  private func getDartBridgeLibraryPath() -> String? {
#if os(iOS)
    guard let frameworkURL = Bundle.main.privateFrameworksURL?
      .appendingPathComponent("dart_bridge.framework")
      .appendingPathComponent("dart_bridge") else {
      return nil
    }
    return frameworkURL.path

#elseif os(macOS)
    guard let pythonBundlePath = getPythonBundlePath() else {
      return nil
    }
    let libDynloadPath = "\(pythonBundlePath)/site-packages"
    let fileManager = FileManager.default
    guard let contents = try? fileManager.contentsOfDirectory(atPath: libDynloadPath) else {
      return nil
    }
    if let soName = contents.first(where: { $0.hasPrefix("dart_bridge") && $0.hasSuffix(".so") }) {
      return "\(libDynloadPath)/\(soName)"
    } else {
      return nil
    }
#else
    return nil
#endif
  }

  private func getPythonModulePaths() -> [String]? {
    guard let pythonBundlePath = getPythonBundlePath() else {
      return nil
    }
    return [
      "\(pythonBundlePath)/site-packages",
      "\(pythonBundlePath)/stdlib",
      "\(pythonBundlePath)/stdlib/lib-dynload"
    ]
  }
}
