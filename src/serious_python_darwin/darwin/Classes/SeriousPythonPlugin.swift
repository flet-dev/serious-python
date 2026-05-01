#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

import Python

public class SeriousPythonPlugin: NSObject, FlutterPlugin {
    
    private static var pythonInitialized = false
    private static var pythonLock = NSLock()
    
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
            let exePath = args["exePath"] as? String ?? ""
            let appPath = args["appPath"] as! String
            let script = args["script"] as? String
            let modulePaths = args["modulePaths"] as? [String] ?? []
            let envVars = args["environmentVariables"] as? [String:String] ?? [:]
            let sync = args["sync"] as? Bool ?? false
            
            NSLog("Swift runPython(appPath: \(appPath), modulePaths: \(modulePaths), sync: \(sync))")
            
            let appDir = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
            
            // bundle root path
            guard let frameworkBundle = Bundle(for: type(of: self)).resourceURL else {
                result(FlutterError(code: "FRAMEWORK_BUNDLE_ERROR", 
                                    message: "Failed to get framework resource URL", 
                                    details: nil))
                return
            }

            let pythonBundleURL = frameworkBundle.appendingPathComponent("python.bundle")

            guard let pythonBundle = Bundle(url: pythonBundleURL) else {
                result(FlutterError(code: "PYTHON_BUNDLE_ERROR", 
                                    message: "Failed to load Python bundle", 
                                    details: pythonBundleURL.path))
                return
            }

            guard let resourcePath = pythonBundle.resourcePath else {
                result(FlutterError(code: "RESOURCE_PATH_ERROR", 
                                    message: "Failed to locate Python bundle resources", 
                                    details: nil))
                return
            }
            
            let pythonPaths: [String] = modulePaths + [
                appDir,
                "\(appDir)/__pypackages__",
                "\(resourcePath)/site-packages",
                "\(resourcePath)/stdlib",
                "\(resourcePath)/stdlib/lib-dynload"
            ]

            setenv("PYTHONINSPECT", "1", 1)
            setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
            setenv("PYTHONNOUSERSITE", "1", 1)
            setenv("PYTHONUNBUFFERED", "1", 1)
            setenv("LC_CTYPE", "UTF-8", 1)
            setenv("PYTHONHOME", resourcePath, 1)
            setenv("PYTHONPATH", pythonPaths.joined(separator: ":"), 1)
            
            // custom env vars
            envVars.forEach { key, value in
                setenv(key, value, 1)
            }
            
            // ensure Python is initialized only once
            Self.ensurePythonInitialized()
            
            // run program either sync or in a thread
            if sync {
                if script == nil {
                    runPythonFile(appPath: appPath, envVars: envVars)
                } else {
                    runPythonScript(script: script!, envVars: envVars)
                }
            } else {
                if script == nil {
                    let t = Thread(target: self, selector: #selector(runPythonFileAsync(_:)), object: ["appPath": appPath, "envVars": envVars])
                    t.start()
                } else {
                    let t = Thread(target: self, selector: #selector(runPythonScriptAsync(_:)), object: ["script": script!, "envVars": envVars])
                    t.start()
                }
            }
            
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private static func ensurePythonInitialized() {
        pythonLock.lock()
        defer { pythonLock.unlock() }
        
        guard !pythonInitialized else { return }
        
        NSLog("Initializing Python interpreter...")
        Py_Initialize()
        if Py_IsInitialized() == 0 {
            NSLog("ERROR: Python initialization failed!")
            return
        }
        // Release GIL and save main thread state to allow other threads to acquire GIL
        PyEval_SaveThread()
        pythonInitialized = true
        NSLog("Python initialized successfully, GIL released.")
    }
    
    @objc func runPythonFile(appPath: String) {
        runPythonFile(appPath: appPath, envVars: [:])
    }
    
    func runPythonFile(appPath: String, envVars: [String: String]) {
        NSLog("runPythonFile entered for: \(appPath)")
        let gstate = PyGILState_Ensure()
        NSLog("GIL acquired")

        // Update os.environ with provided environment variables
        if !envVars.isEmpty {
            var updateScript = "import os\n"
            for (key, value) in envVars {
                let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
                updateScript += "os.environ['\(key)'] = '\(escapedValue)'\n"
            }
            NSLog("Updating os.environ:\n\(updateScript)")
            let ret = PyRun_SimpleString(updateScript)
            if ret != 0 {
                NSLog("Failed to update os.environ")
                PyErr_Print()
            }
        }

        let file = fopen(appPath, "r")
        let result = PyRun_SimpleFileEx(file, appPath, 1)
        if result != 0 {
            NSLog("Python program completed with error.")
            PyErr_Print()
        } else {
            NSLog("Python file executed successfully")
        }
        
        PyGILState_Release(gstate)
        NSLog("GIL released, runPythonFile finished")
    }
    
    @objc func runPythonFileAsync(_ arg: NSDictionary) {
        let appPath = arg["appPath"] as! String
        let envVars = arg["envVars"] as! [String: String]
        NSLog("runPythonFileAsync starting for: \(appPath)")
        runPythonFile(appPath: appPath, envVars: envVars)
        NSLog("runPythonFileAsync thread finished")
    }

    @objc func runPythonScript(script: String) {
        runPythonScript(script: script, envVars: [:])
    }
    
    func runPythonScript(script: String, envVars: [String: String]) {
        NSLog("runPythonScript entered")
        let gstate = PyGILState_Ensure()
        NSLog("GIL acquired")

        // Update os.environ with provided environment variables
        if !envVars.isEmpty {
            var updateScript = "import os\n"
            for (key, value) in envVars {
                let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
                updateScript += "os.environ['\(key)'] = '\(escapedValue)'\n"
            }
            NSLog("Updating os.environ:\n\(updateScript)")
            let ret = PyRun_SimpleString(updateScript)
            if ret != 0 {
                NSLog("Failed to update os.environ")
                PyErr_Print()
            }
        }

        let result = PyRun_SimpleString(script)
        if result != 0 {
            NSLog("Python script completed with error.")
            PyErr_Print()
        } else {
            NSLog("Python script executed successfully")
        }
        
        PyGILState_Release(gstate)
        NSLog("GIL released, runPythonScript finished")
    }
    
    @objc func runPythonScriptAsync(_ arg: NSDictionary) {
        let script = arg["script"] as! String
        let envVars = arg["envVars"] as! [String: String]
        NSLog("runPythonScriptAsync starting")
        runPythonScript(script: script, envVars: envVars)
        NSLog("runPythonScriptAsync thread finished")
    }
}
