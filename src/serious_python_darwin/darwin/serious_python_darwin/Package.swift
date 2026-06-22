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

// dart_bridge: static archive, link-only. Its FFI exports are resolved at runtime
// via dlsym (Dart's `DynamicLibrary.process()` and Python's `import dart_bridge`),
// so the whole archive must be retained against the linker's -dead_strip. We
// force-load JUST this archive rather than using a global -all_load: SwiftPM
// applies a target's linkerSettings to the FINAL app executable link, so a global
// -all_load there would force-load EVERY static archive on the link line —
// including plugins that statically bundle the same third-party code (e.g.
// flet-video/media_kit and flet-rive both embed miniaudio), which then collide
// with thousands of duplicate symbols. -force_load on dart_bridge alone mirrors
// what the CocoaPods podspec did via `pod_target_xcconfig` (scoped to this pod's
// own inputs — only dart_bridge among them is a static archive). On macOS the
// xcframework has a single universal slice with a stable path, so we resolve it
// here. On iOS, plugin pods link as dynamic frameworks (no static-archive
// collision) and device/simulator use different slice paths, so the
// slice-agnostic -all_load is kept there (see linkerSettings below).
var macosDartBridgeForceLoad: [String] = []
if staged("dart_bridge.xcframework") {
    binaryTargets.append(.binaryTarget(name: "dart_bridge", path: "dart_bridge.xcframework"))
    deps.append("dart_bridge")
    let xc = pkgDir.appendingPathComponent("dart_bridge.xcframework")
    if let slices = try? FileManager.default.contentsOfDirectory(
        at: xc, includingPropertiesForKeys: nil) {
        for slice in slices.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where slice.lastPathComponent.hasPrefix("macos") {
            let lib = slice.appendingPathComponent("libdart_bridge.a")
            if FileManager.default.fileExists(atPath: lib.path) {
                macosDartBridgeForceLoad = ["-force_load", lib.path]
            }
        }
    }
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
                .unsafeFlags(["-ObjC"]),
                // iOS: slice-agnostic -all_load. Plugin pods link as dynamic
                // frameworks, so dart_bridge is the only static archive in scope —
                // nothing else to double-load. (device/simulator slice paths differ,
                // so a single -force_load path isn't possible here.)
                .unsafeFlags(["-all_load"], .when(platforms: [.iOS])),
                // macOS: force-load ONLY dart_bridge (resolved above), never a global
                // -all_load — see the note where macosDartBridgeForceLoad is built.
                .unsafeFlags(macosDartBridgeForceLoad, .when(platforms: [.macOS])),
                .linkedLibrary("c++"),
            ]
        ),
    ] + binaryTargets
)
