// swift-tools-version: 5.9
import PackageDescription
import Foundation

// === serious_python_darwin — Swift Package Manager manifest ===
//
// Dual build system: this package builds the plugin under SwiftPM; the sibling
// `serious_python_darwin.podspec` builds the same Sources/ under CocoaPods.
//
// The Python runtime, dart_bridge, the app's native C-extensions, and the
// stdlib/site-packages/app trees are NOT committed. serious_python's `package`
// command (driven by `flet build`) materializes them into THIS package directory
// before `flutter build`, exactly as the CocoaPods `prepare_command` does:
//
//   <pkg>/Python-ios.xcframework, Python-macos.xcframework   Python runtime (dynamic)
//   <pkg>/dart_bridge.xcframework                            FFI transport (static)
//   <pkg>/extra-xcframeworks/*.xcframework                   iOS native extensions
//                                                            (stdlib lib-dynload + site-packages)
//   <pkg>/Sources/serious_python_darwin/Resources/{stdlib,site-packages,app}
//
// On iOS, native extensions ship as embedded+signed frameworks (CPython's finder
// dlopen's them by their bundled path). On macOS they ride flat inside the
// site-packages / stdlib resource trees and load in place.
//
// CACHE-BUST CONTRACT: SwiftPM caches the resolved package graph keyed on this
// manifest's TEXT + the environment variables it reads — NOT on the staged dirs it
// enumerates. So the package step exports `SP_NATIVE_SET`, a hash over everything it
// staged (Python full version, dart_bridge version, the sorted extension set, the
// resource trees). Reading it here makes it a tracked key, so any change to the
// staged inputs forces re-resolution. `SERIOUS_PYTHON_VERSION` (the project's
// version-selection contract) is read for the same reason.
let env = ProcessInfo.processInfo.environment
_ = env["SP_NATIVE_SET"]
_ = env["SERIOUS_PYTHON_VERSION"]

let pkgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
func staged(_ rel: String) -> Bool {
    FileManager.default.fileExists(atPath: pkgDir.appendingPathComponent(rel).path)
}

// Native binary targets + their plugin-target dependencies. All existence-guarded so
// the manifest still parses in an unstaged checkout (IDE / `dart pub get`); a real
// `flutter build` always stages first.
var binaryTargets: [Target] = []
var deps: [Target.Dependency] = [.product(name: "FlutterFramework", package: "FlutterFramework")]

// dart_bridge: DYNAMIC framework -> embedded + auto-signed in the app. Its FFI
// entry points (serious_python_run, DartBridge_*, PyInit_dart_bridge) are
// EXPORTED from the loaded framework, so the dlsym lookups that Dart
// (`DynamicLibrary.process()`) and Python (`import dart_bridge`) perform resolve
// at runtime. A static library would instead be linked into the app executable,
// which does not export its symbols (and the release build strips them), so
// dlsym would fail with "Failed to lookup symbol 'serious_python_run'". Shipping
// it dynamic mirrors the Android `.so` (CMake SHARED) that already works — see
// flet-dev/dart-bridge apple/build_xcframework.sh. No -all_load/-force_load or
// keep-alive is needed anymore: the framework is a loaded image, not archive
// members that must be pulled in and kept against -dead_strip.
if staged("dart_bridge.xcframework") {
    binaryTargets.append(.binaryTarget(name: "dart_bridge", path: "dart_bridge.xcframework"))
    deps.append("dart_bridge")
}
// Python.framework: dynamic -> embedded + auto-signed. iOS and macOS ship separate
// xcframeworks, so each is platform-conditional.
if staged("Python-ios.xcframework") {
    binaryTargets.append(.binaryTarget(name: "Python_ios", path: "Python-ios.xcframework"))
    deps.append(.target(name: "Python_ios", condition: .when(platforms: [.iOS])))
}
if staged("Python-macos.xcframework") {
    binaryTargets.append(.binaryTarget(name: "Python_macos", path: "Python-macos.xcframework"))
    deps.append(.target(name: "Python_macos", condition: .when(platforms: [.macOS])))
}
// iOS native C-extensions: each staged *.xcframework -> embedded+signed framework.
let extraDir = pkgDir.appendingPathComponent("extra-xcframeworks")
if let items = try? FileManager.default.contentsOfDirectory(
    at: extraDir, includingPropertiesForKeys: nil) {
    for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where item.pathExtension == "xcframework" {
        let name = item.deletingPathExtension().lastPathComponent
        binaryTargets.append(.binaryTarget(name: name, path: "extra-xcframeworks/\(name).xcframework"))
        deps.append(.target(name: name, condition: .when(platforms: [.iOS])))
    }
}

let package = Package(
    name: "serious_python_darwin",
    platforms: [.iOS("13.0"), .macOS("11.0")],
    products: [
        .library(name: "serious-python-darwin", targets: ["serious_python_darwin"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "serious_python_darwin",
            dependencies: deps,
            resources: [
                // Staged trees. .copy (verbatim) preserves the layout PYTHONHOME /
                // PYTHONPATH expect; committed `.keep` placeholders keep these paths
                // valid (and Bundle.module generated) in an unstaged checkout.
                .copy("Resources/stdlib"),
                .copy("Resources/site-packages"),
                .copy("Resources/app"),
            ],
            linkerSettings: [
                // dart_bridge is now a dynamic framework (embedded, symbols
                // exported), so no -all_load / -force_load is needed to retain it.
                .unsafeFlags(["-ObjC"]),
                .linkedLibrary("c++"),
            ]
        ),
    ] + binaryTargets
)
