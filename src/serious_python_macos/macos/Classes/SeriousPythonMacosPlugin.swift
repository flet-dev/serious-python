import Cocoa
import FlutterMacOS

public class SeriousPythonMacosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "serious_python_macos", binaryMessenger: registrar.messenger)
    let instance = SeriousPythonMacosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "setEnvironmentVariable":
      let args: [String: Any] = call.arguments as? [String: Any] ?? [:]
      let name = args["name"] as! String
      let value = args["value"] as! String
      setenv(name, value, 1)
      result("setenv(name: \(name), value: \(value))")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
