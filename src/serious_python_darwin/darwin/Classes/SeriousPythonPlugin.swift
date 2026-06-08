#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import FlutterMacOS
#endif

import Python

public class SeriousPythonPlugin: NSObject, FlutterPlugin {

    public typealias PyInitFunction = @convention(c) () -> UnsafeMutablePointer<PyObject>?

    private struct PythonExtensionEntry {
        // PyImport_AppendInittab does not copy the name string; the storage must
        // outlive the interpreter. We strdup on register and intentionally leak.
        let name: UnsafeMutablePointer<CChar>
        let initFn: PyInitFunction
    }

    private static var registeredExtensions: [PythonExtensionEntry] = []
    private static let registrationLock = NSLock()

    /// Register a statically linked Python C extension to be made available as a
    /// built-in module on every Py_Initialize. Intended for iOS, where dlopen of
    /// late-loaded .so extensions is forbidden, but available on macOS too so
    /// callers don't need platform conditionals.
    ///
    /// Must be called before serious_python's first runPython invocation. Calling
    /// twice with the same name is the caller's responsibility to avoid.
    public static func registerPythonExtension(name: String, initFn: PyInitFunction) {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard let copied = strdup(name) else {
            NSLog("[SeriousPython] strdup failed for extension name \(name)")
            return
        }
        registeredExtensions.append(PythonExtensionEntry(name: copied, initFn: initFn))
    }

    private func applyRegisteredExtensions() {
        SeriousPythonPlugin.registrationLock.lock()
        let entries = SeriousPythonPlugin.registeredExtensions
        SeriousPythonPlugin.registrationLock.unlock()

        for entry in entries {
            if PyImport_AppendInittab(entry.name, entry.initFn) != 0 {
                NSLog("[SeriousPython] PyImport_AppendInittab failed for \(String(cString: entry.name))")
            }
        }
    }

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
        applyRegisteredExtensions()
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
        applyRegisteredExtensions()
        Py_Initialize()

        // run app
        let result = PyRun_SimpleString(script)
        if (result != 0) {
            print("Python script completed with error.")
        }

        Py_Finalize()
    }
}
