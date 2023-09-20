import Flutter
import UIKit
import Python

public class SeriousPythonPlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "serious_python", binaryMessenger: registrar.messenger())
        let instance = SeriousPythonPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "runPython":
            let args: [String: Any] = call.arguments as? [String: Any] ?? [:]
            let appPath = args["appPath"] as! String
            let modulePaths = args["modulePaths"] as? [String] ?? []
            let envVars = args["environmentVariables"] as? [String:String] ?? [:]
            let sync = args["sync"] as? Bool ?? false
            
            NSLog("Swift runPython(appPath: \(appPath), modulePaths: \(modulePaths))")
            
            let appDir = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
            
            // bundle root path
            guard let resourcePath = Bundle(for: type(of: self)).resourcePath else { return }
            
            let pythonPaths: [String] = modulePaths + [
                appDir,
                "\(appDir)/__pypackages__",
                resourcePath,
                "\(resourcePath)/lib/site-packages.zip",
                "\(resourcePath)/lib/python3.10"
            ]

            setenv("PYTHONINSPECT", "1", 1)
            setenv("PYTHONOPTIMIZE", "2", 1)
            setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
            setenv("PYTHONNOUSERSITE", "1", 1)
            setenv("PYTHONUNBUFFERED", "1", 1)
            setenv("LC_CTYPE", "UTF-8", 1)
            setenv("PYTHONHOME", resourcePath, 1)
            setenv("PYTHONPATH", pythonPaths.joined(separator: ":"), 1)
            
            // custom env vars
            envVars.forEach {v in
                setenv(v.key, v.value, 1)
            }
            
            // run program either sync or in a thread
            if (sync) {
                runPython(appPath: appPath)
            } else {
                let t = Thread(target: self, selector: #selector(runPython), object: appPath)
                t.start()
            }
            
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @objc func runPython(appPath: String) {
        Py_Initialize()
        
        // run app
        let file = fopen(appPath, "r")
        let result = PyRun_SimpleFileEx(file, appPath, 1)
        if (result != 0) {
            print("Python program completed with error.")
        }
        
        Py_Finalize()
    }
}
