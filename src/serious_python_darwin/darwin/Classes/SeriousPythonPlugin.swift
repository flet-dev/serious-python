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
        case "getPlatformVersion":
            #if os(iOS)
                result("iOS " + UIDevice.current.systemVersion)
            #else
                result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
            #endif
        case "runPython":
            let args: [String: Any] = call.arguments as? [String: Any] ?? [:]
            let appPath = args["appPath"] as! String
            let script = args["script"] as? String
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
                "\(resourcePath)/lib/python3.11",
                "\(resourcePath)/python-stdlib",
                "\(resourcePath)/python-stdlib/lib-dynload"
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
                if (script == nil) {
                    runPythonFile(appPath: appPath)
                } else {
                    runPythonScript(script: script!)
                }
            } else {
                if (script == nil) {
                    let t = Thread(target: self, selector: #selector(runPythonFile), object: appPath)
                    t.start()
                } else {
                    let t = Thread(target: self, selector: #selector(runPythonScript), object: script!)
                    t.start()
                }
            }
            
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    @objc func runPythonFile(appPath: String) {
        Py_Initialize()
        
        // run app
        let file = fopen(appPath, "r")
        let result = PyRun_SimpleFileEx(file, appPath, 1)
        if (result != 0) {
            print("Python program completed with error.")
        }
        
        Py_Finalize()
    }

    @objc func runPythonScript(script: String) {
        Py_Initialize()
        
        // run app
        let result = PyRun_SimpleString(script)
        if (result != 0) {
            print("Python script completed with error.")
        }
        
        Py_Finalize()
    }
}
