## 4.5.0

* **iOS/macOS: provider-built XCFrameworks are now staged byte-for-byte, and their SDK-origin signatures are verified.** `Python.xcframework`, `dart_bridge.xcframework`, and every stdlib extension framework arrive pre-built from flet-dev/python-build and flet-dev/dart-bridge. serious_python no longer rewrites anything inside them: the `SERIOUS_PYTHON_BUNDLE_ID` pass now applies **only** to frameworks built here from the app's own wheels, which are generated in a separate directory, mutated there, and merged with the untouched provider artifacts afterwards. `reconcile_framework_install_names` (which rewrites Mach-O headers and re-signs ad-hoc) likewise never reaches a provider binary.
* **This retracts the reasoning in 4.4.2.** That entry claimed "a signature applied at the source can't matter", on the grounds that Xcode's `codesign -f` at embed and `exportArchive` overwrites it. The overwrite is real but the conclusion was wrong: Xcode *separately* records the state of each `.xcframework` as its publisher shipped it, and writes that into the IPA as `Signatures/<name>.xcframework-ios.signature` with `signed` and `isSecureTimestamp` flags. `ITMS-91065: Missing signature` reports on **those receipts**, not on the embedded copy. Namespacing `CFBundleIdentifier` under the host app was therefore not a fix, and was actively counterproductive — the plist edit invalidated the very signature the receipt reports on. The 4.4.2 identifier rewrite is reverted for provider frameworks and kept for locally built ones, where it is harmless and matches CPython's convention.
* **New: provider integrity is checked at every staging step.** A SHA-256 manifest of the provider XCFrameworks is recorded when they are extracted, and re-checked after site-package synchronization and after SwiftPM staging. Any file that changed fails the build. `SERIOUS_PYTHON_VERIFY_PROVIDER_SIGNATURES` (`warn` default / `require` / `off`) additionally checks that each provider XCFramework carries a real, securely timestamped publisher signature; `SERIOUS_PYTHON_EXPECTED_TEAM_ID` pins the expected Apple Team ID. The default is `warn` so that pinning an older, pre-signing `python-build` or `dart-bridge` release still builds — use `require` for App Store submissions.
* **iOS: use the Swift Package Manager path for App Store submissions.** The CocoaPods path installs the stdlib and site-package extensions by copying the *inner* `.framework` bundles in a `Pods-Runner-frameworks.sh` script phase; Xcode writes SDK-origin receipts only for xcframeworks it consumes as declared binary dependencies, so that path cannot produce complete receipts no matter how the source is signed. It now emits an Xcode `warning:` saying so. The SwiftPM path declares them as `binaryTarget`s and is unaffected.
* Provider identifiers are now assigned upstream and are stable: `dev.flet.python.runtime` for the Python runtime, `dev.flet.python.<module>` for each stdlib extension, `dev.flet.dartbridge` for the bridge. They no longer depend on the consuming app, which is what allows one publisher signature to cover every app.
* Re-pins the bundled python-build snapshot to **20260729** (`dart_bridge` **1.6.1 → 1.7.0**). No Python version moved — **3.12.13 / 3.13.14 / 3.14.6** and Pyodide are unchanged from 20260727. What did change is that every Apple XCFramework in that release, and `dart_bridge.xcframework` in 1.7.0, is now signed by the Flet publishing team's Apple Distribution identity with a secure timestamp: verified on the published artifacts as `Authority=Apple Distribution: Appveyor Systems Inc. (GXXRQJK434)`, a real `Timestamp=`, and an outer `_CodeSignature/CodeResources` — 56 XCFrameworks in `python-ios-dart-3.14.6`, plus the macOS and mobile-forge runtimes. See flet-dev/python-build#37 and flet-dev/dart-bridge#13.

## 4.4.2

* **iOS: framework bundle identifiers are now namespaced under the host app.** Every Python C-extension ships as its own embedded framework, and each carried a fixed `org.python.<module>` `CFBundleIdentifier` — `org.python.ssl`, `org.python.hashlib`, … — byte-identical in every app ever built with serious_python. Set `SERIOUS_PYTHON_BUNDLE_ID` to the app's bundle identifier and they become `com.example.myapp.-ssl` instead, matching what CPython's own iOS support does when it converts a `.so` into a framework. This matters because a framework's bundle identifier also becomes its **code signing identifier**, which is the one field that survives the `codesign -f` Xcode applies at embed and again at `exportArchive`. `Python.framework` is covered too — it was `org.python.python` in every app; nothing resolves it by identifier (the string appears in no shipped binary and there are no `CFBundleGetBundleWithIdentifier` lookups), so the rename is inert at runtime. `dart_bridge.framework` is deliberately left at `dev.flet.dartbridge`, which is already a vendor-owned identifier rather than a shared placeholder. Unset, or set to something that isn't a valid bundle identifier, leaves the old defaults in place and prints a warning. `flet build` supplies it from your app's configured bundle id (flet-dev/flet#6731).
* **iOS: generated frameworks now carry Xcode's build-provenance keys in their `Info.plist`.** Every framework built from a `lib-dynload` `.so` — `_ssl`, `_hashlib`, and the rest — previously shipped ten hand-written keys and not a single `DT*` key, so to Apple's static analysis the bundle didn't look like anything Xcode had produced. They now carry the same key set Xcode stamps into a real framework (`BuildMachineOSBuild`, `DTCompiler`, `DTPlatformBuild`, `DTPlatformName`, `DTPlatformVersion`, `DTSDKBuild`, `DTSDKName`, `DTXcode`, `DTXcodeBuild`, `UIDeviceFamily`, and `UIRequiredDeviceCapabilities` on the device slice), resolved from the SDK the release was built with. The simulator slice is also labelled correctly now — it previously claimed `CFBundleSupportedPlatforms=iPhoneOS`. See flet-dev/python-build#36.
* Both changes above are hypotheses under test for the `ITMS-91065: Missing signature` App Store rejection in flet-dev/flet#6724, **neither is a confirmed fix**. The shared bundle identifier is the stronger of the two: it accounts for every outcome we could find (BeeWare namespaces under the app and has no reports; a third-party OpenSSL xcframework with its own vendor identifier is reported to pass; our `org.python.*` and one other project's independent identifier both draw the rejection). Two further candidates were ruled out experimentally: a signature applied at the source can't matter (re-signing the way `exportArchive` does destroys the certificate chain, team identifier and timestamp, leaving only the identifier string, which is derived from `CFBundleIdentifier` for an unsigned framework anyway), and the privacy manifest can't be the differentiator (a third-party OpenSSL xcframework the App Store accepts ships an empty stub, and our frameworks already carry a manifest — Apple emits no `ITMS-91061` alongside the rejection). The check only fires for new apps, or updates that newly add a listed SDK, so existing published apps are unaffected either way.
* Re-pins the bundled python-build snapshot to **20260727**. No versions moved: Python (**3.12.13 / 3.13.14 / 3.14.6**), Pyodide, and `dart_bridge` **1.6.1** are unchanged from 20260726, and the `Info.plist` change above is the only functional difference on any platform.

## 4.4.1

* **iOS: `_ssl.framework` and `_hashlib.framework` now carry OpenSSL's official privacy manifest.** Both extensions statically link OpenSSL, so Apple's App Store scan identifies them as containing BoringSSL / openssl_grpc — a listed third-party SDK that must declare a privacy manifest. The bundled `PrivacyInfo.xcprivacy` was a stub: `NSPrivacyAccessedAPITypes` was an empty array, and it carried an `NSPrivacyUsesNonStandardAPIs` key that isn't part of Apple's schema. It is now byte-identical to the manifest OpenSSL publishes for its Apple builds, declaring the file-timestamp API access the library actually performs (`NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1`). See flet-dev/python-build#35.
* This does **not** resolve the `ITMS-91065: Missing signature` App Store rejection reported in flet-dev/flet#6724, and shouldn't be read as a fix for it. That rejection cites the same two frameworks but arrives with no accompanying `ITMS-91061`, so Apple does find the manifest. Inspecting a built `.ipa` confirms the frameworks reach Apple signed — valid Apple Distribution authority and team ID, with the manifest sealed into `_CodeSignature/CodeResources` — and that Xcode re-signs every embedded framework with the submitting team's identity at both the embed and `exportArchive` steps, overwriting whatever signature the vendor applied. Root cause is still open; this change removes the one verifiable defect so it isn't a confound.
* Re-pins the bundled python-build snapshot to **20260726**. No versions moved: Python (**3.12.13 / 3.13.14 / 3.14.6**), Pyodide, and `dart_bridge` **1.6.1** are all unchanged from 20260725, and the privacy manifest above is the only functional difference on any platform.

## 4.4.0

* **iOS/macOS: `dart_bridge` now ships as a dynamic framework**, fixing built iOS apps crashing at startup with `Failed to lookup symbol 'serious_python_run': dlsym(RTLD_DEFAULT, serious_python_run): symbol not found`. `dart_bridge`'s FFI entry points (`serious_python_run`, `DartBridge_InitDartApiDL`, `DartBridge_EnqueueMessage`, `PyInit_dart_bridge`) are resolved at runtime via `dlsym` — from Dart through `DynamicLibrary.process()` and from Python through `import dart_bridge`. It previously shipped as a **static** archive linked into the host app *executable*, and an iOS executable exports nothing to the dynamic symbol table by default (the release build also strips local symbols), so those lookups failed. Only release/archive (device) builds were affected — debug/simulator builds don't dead-strip, so the failure did not reproduce there. Android was never affected: its `dart_bridge` is a dynamic `.so`, which exports its symbols. `dart_bridge` **1.6.1** now builds `dart_bridge.xcframework` as a dynamic framework (see flet-dev/dart-bridge#11 and #12), so it is embedded + signed into the app like `Python.xcframework` and its symbols stay exported. The SwiftPM `-all_load` / `-force_load` retention, the CocoaPods `-all_load`, and the plugin's dead-strip keep-alive references are all removed — a loaded image needs none of them.
* Re-pins the bundled python-build snapshot to **20260725** (`dart_bridge` **1.5.1 → 1.6.1**). Python versions (**3.12.13 / 3.13.14 / 3.14.6**) are unchanged and the iOS/macOS CPython runtimes are byte-identical to 20260720.

## 4.3.6

* Re-pins the bundled python-build snapshot to **20260720** (`dart_bridge` **1.5.0 → 1.5.1**). 1.5.1 is a Windows-only UTF-8 startup fix (see `serious_python_windows` 4.3.6); the iOS/macOS runtimes are functionally unchanged from 20260719.

## 4.3.4

* Re-pins the bundled python-build snapshot to **20260719** (previously 20260714). The snapshot un-prunes `_pyrepl` on Windows/Linux desktop (fixing a 3.14 `pydoc`/`pdb` crash — see `serious_python_windows` / `serious_python_linux` 4.3.4); iOS/macOS already shipped `_pyrepl` (un-pruned in 4.3.2), so these runtimes are byte-identical to 20260714. No iOS/macOS-affecting changes.

## 4.3.3

* Version bump aligning with the `serious_python_*` 4.3.3 release (a Windows build fix). No iOS/macOS-affecting changes.

## 4.3.2

* **iOS: reconcile framework install-names for interdependent bundled dylibs** ([#223](https://github.com/flet-dev/serious-python/issues/223)). Site-package `.so`/`.dylib`s are wrapped into frameworks named by their dotted relative path (`opt/lib/libarrow.dylib` → `opt.lib.libarrow.framework/opt.lib.libarrow`), but the Mach-O install-id and every interdependent `@rpath` reference were left at their original bare name (`@rpath/libarrow.dylib`). Because each framework is a `Package.swift` binaryTarget linked at launch, dyld could not resolve `@rpath/libarrow.dylib` (it looks for `Frameworks/libarrow.dylib`, which does not exist) and the app crashed **before Python started** — hitting any package that bundles a chain of interdependent libs (pyarrow's `libarrow`/`libarrow_compute`/`libarrow_python`, llama-cpp-python's `libggml*`/`libllama`). A new reconcile pass, run after `sync_site_packages` frameworks the libs, sets each framework's own install-id to `@rpath/<fw>.framework/<fw>` and rewrites every dependency pointing at a sibling's old id to that framework path, then re-signs. The Python/stdlib xcframeworks are left untouched. (This supersedes the 4.2.1 approach of preserving `.dylib` install-names, which only worked when every sibling happened to be loaded first.)
* The reconcile pass fails the build — rather than silently swallowing — on a genuine `install_name_tool`/`codesign` error, notably insufficient Mach-O header space to grow a load command (which would otherwise leave a bare `@rpath` ref and reproduce the launch crash), and records every framework slice's old install-id so a lib with divergent per-slice install names has all slices rewritten.
* Bump the bundled python-build snapshot to `20260714` (Python/`dart_bridge` versions are unchanged), with two iOS fixes:
  * `_pyrepl` is no longer pruned from the bundled stdlib: Python **3.14**'s `pdb` imports `_pyrepl` at module load, so anything importing `pdb` (e.g. pytest's debugging plugin) died with `ModuleNotFoundError: No module named '_pyrepl'` on iOS (3.13's `pdb` doesn't import it).
  * The `_posixshmem` extension is now built into the iOS runtimes: `multiprocessing.resource_tracker` — imported transitively by `import multiprocessing` (e.g. scikit-learn → joblib) — unconditionally imports it on posix, so with `_multiprocessing` enabled (since `20260701`) but `_posixshmem` missing, any `multiprocessing` user died with `ModuleNotFoundError: No module named '_posixshmem'`. Process *spawning* remains unsupported in the iOS sandbox — this only makes the shared-memory module importable.

## 4.3.1

* Version bump aligning with the `serious_python_*` 4.3.1 release.

## 4.3.0

* Bump `dart_bridge` to **1.5.0** (python-build snapshot `20260708`): multiprocessing child-interception exports (`serious_python_is_mp_invocation` / `serious_python_main`), kept alive against the host link's `-dead_strip` both by `__attribute__((used))` in the archive and by keep-alive references in `SeriousPythonPlugin.swift`. See the `serious_python` 4.3.0 notes.
* `prepare_macos.sh` / `prepare_ios.sh`: the extracted `dart_bridge.xcframework` in `dist_*` is now keyed to the dart_bridge version (`.dart_bridge_version` marker) — previously a version bump kept staging the stale extraction from the earlier version.
* `PYTHONINSPECT=1` is no longer set by any platform implementation. It had no effect on the embedded interpreter, but it leaked into the process environment where any *real* interpreter child (e.g. a serviced multiprocessing worker) would inherit it and hang in interactive mode after its command completed.

## 4.2.1

* Framework-ize ctypes `.dylib` shared libs (not just `.so` C-extensions) when syncing iOS site-packages, so `.dylib`-shipping packages (e.g. `llama-cpp-python`) load on the **iOS simulator** instead of failing `dlopen` with `incompatible platform (have 'iOS', need 'iOS-simulator')`. Each `.dylib` becomes a device+simulator xcframework + `.fwork` pointer, exactly like `.so`; unlike `.so` (whose id is rewritten to the framework path), the `.dylib` install-name is preserved so multi-lib packages resolve their sibling libs. The `.so` path is unchanged.
* Bump the bundled python-build snapshot to `20260701`: the iOS runtime now builds the `_multiprocessing` extension (importable, not spawnable). Python/`dart_bridge` versions are unchanged from `20260630`.

## 4.2.0

* Bump the bundled python-build snapshot to `20260630` (`dart_bridge` `1.4.1`); aligns with the `serious_python_*` 4.2.0 release.

## 4.1.1

* Version bump aligning with the `serious_python_*` 4.1.1 release.

## 4.1.0

* Version bump aligning with the `serious_python_*` 4.1.0 release.

## 4.0.0

* **Swift Package Manager support (dual with CocoaPods).** The plugin now builds under SPM as well as CocoaPods, so apps can use either integration (CocoaPods goes read-only in December 2026; Flutter ships SPM on by default since 3.44). A new `darwin/serious_python_darwin/Package.swift` builds the same Swift source as the podspec, with `getResourcePath` resolving `Bundle.module` under SPM (`#if SWIFT_PACKAGE`) and the framework `python.bundle` under CocoaPods.
  * SPM has no pod-install hook, so the staging the podspec `prepare_command` does runs on the host before `flutter build` instead: `prepare_spm.sh` assembles the dist (`prepare_<platform>.sh` + `sync_site_packages.sh`) and `stage_spm.sh` maps it into the package layout — `Python-{ios,macos}.xcframework` + `dart_bridge.xcframework` as local-path binary targets, the iOS native C-extensions enumerated from `extra-xcframeworks/`, and `stdlib`/`site-packages`/`app` as `.copy` resources. On iOS the extensions ship as embedded, signed frameworks (CPython's `.fwork` finder resolves them); on macOS they load flat from the resource trees.
  * The manifest reads `SP_NATIVE_SET` (a hash of the staged native set) so SwiftPM re-resolves when requirements / app / Python version change — SwiftPM caches its package graph on manifest text + environment, not on the staged dirs it enumerates.
  * The **SPM path** needs Flutter **3.44** / Dart **3.11**; the plugin's minimum is unchanged because `Package.swift` is dormant on older Flutter (which uses the CocoaPods path).
* `prepareApp()` returns the app dir from the `python.bundle` resource (`<resourcePath>/app`); the app's Python sources ship unpacked as an `app` resource bundle next to `stdlib` + `site-packages` (no first-launch extraction).
* Version bump aligning with the `serious_python_*` 4.0.0 release.

## 3.0.0

* **In-process Python (dart_bridge FFI).** The Python lifecycle is absorbed into `dart_bridge.xcframework` (from `flet-dev/dart-bridge` **1.4.0**) instead of a socket transport; the Swift plugin registers the dart_bridge inittab, the pod is declared `static_framework` for xcframework vendoring, and the embedded `Python.app` is stripped from `Python.framework`.
* **Breaking change:** requires Flutter **3.44.2**.
* The podspec resolves the Python version from the generated `python_versions.properties` (a snapshot of python-build's `manifest.json`) and passes the full version, build date and `dart_bridge` version to `prepare_ios.sh` / `prepare_macos.sh` (`dart_bridge_version` is `$4`); `SERIOUS_PYTHON_VERSION` is the knob, the per-field env vars are escape hatches. The prepare scripts re-extract `dist_ios` / `dist_macos` when the selected version changes (a version marker) so a clean build can't mix C-extension ABIs.
* Remove the scaffold `getPlatformVersion` method.

## 2.0.0

* **Breaking change:** default bundled Python version is now 3.14 (was 3.12). Apps built without an explicit `SERIOUS_PYTHON_VERSION` env var pull `python-ios-dart-3.14.tar.gz` / `python-macos-dart-3.14.tar.gz` from `flet-dev/python-build`. Set `SERIOUS_PYTHON_VERSION=3.12` to preserve the previous default.
* Multi-version Python support. `python_version` in `serious_python_darwin.podspec` reads from `SERIOUS_PYTHON_VERSION`; `prepare_ios.sh` / `prepare_macos.sh` already took the version as `$1` and download the matching tarballs.

## 1.0.1

### Improvements

* Cache downloaded Python distribution tarballs (`python-android-dart-<py>-<abi>.tar.gz`) across builds. The `downloadDistArchive_*` Gradle tasks now write to a persistent cache directory — `$FLET_CACHE_DIR/python-build/v<python_version>/` if the env var is set, otherwise `~/.flet/cache/python-build/v<python_version>/` — and use `onlyIfModified true` + `useETag "all"` so subsequent builds issue a conditional GET (`If-None-Match` / `If-Modified-Since`) against `objects.githubusercontent.com` instead of re-downloading 30–100 MB per ABI per build. When the upstream release republishes a tarball at the same URL (e.g. a Python patch update under the existing `v<py>` release), the validators flip and the cache refreshes automatically; otherwise the build skips the download entirely. `tempAndMove true` guards against partial downloads being kept in the cache ([flet-dev/flet#6555](https://github.com/flet-dev/flet/discussions/6555), [#208](https://github.com/flet-dev/serious-python/pull/208)) by @FeodorFitsner.

### Bug fixes

* Set `PIP_REQUIRE_VIRTUALENV=false` for `pip install` in the `package` command so packaging works in environments where users have globally exported `PIP_REQUIRE_VIRTUALENV=true` ([#202](https://github.com/flet-dev/serious-python/pull/202), [#204](https://github.com/flet-dev/serious-python/pull/204)) by @FeodorFitsner.

## 1.0.0

* **Breaking change:** `--platform` argument value `Pyodide` has been renamed to `Emscripten` to match what `platform.system()` returns in the Pyodide runtime, so PEP 508 markers like `platform_system != 'Emscripten'` work consistently.

## 0.9.12

* Fix web packaging to skip `site-packages` when appropriate ([#199](https://github.com/flet-dev/serious-python/pull/199)).

## 0.9.11

* Disable user-site packages in pip environment ([#195](https://github.com/flet-dev/serious-python/pull/195)).

## 0.9.10

* Android: Add debug logs and deduplicate FFI imports.
* Android: Invalidate extracted assets when version keys change.

## 0.9.9

* Add zipDirectoryPosix to create POSIX-compliant app archives on Windows.
* Enforce C++20 standard for `serious_python` plugin build.
* Fix: Normalize `WINDIR` path for bundled DLLs in CMake.
* Fix Logcat logging crash on some Android devices.

## 0.9.8

* Fix logging on Android.

## 0.9.7

* Fix app restart on Android 10.
* Redirect Python output to logcat.

## 0.9.6

* Make zipDirectory call asynchronous.

## 0.9.5

* Bump `archive` to `^4.0.7`.
* Fixed iOS framework identifier generation.

## 0.9.4

* 16 KB memory page support for Android 15+ (by [@ReYaNOW](https://github.com/ReYaNOW)).

## 0.9.3

* Fix: Hidden files in site-packages are skipped when building macOS app.
* Fix: Do not delete package metadata in `.dist-info` directories ([#164](https://github.com/flet-dev/serious-python/issues/164)).

## 0.9.2

* Breaking change: multiple `--requirements` options of `package` command must be passed as `--requirements DEP_1 --requirements DEP_2 ...` (or `-r DEP_1 -r DEP_2 ...`) instead of `-r DEP_1,DEP_2,...` to support dependency specifications with commas, e.g. `pandas>=2.2,<3`.
* Fix site-packages packaging for Pyodide platform.

## 0.9.1

* Fix `serious_python` to work on macOS 12 Monterey and built with Xcode 14.

## 0.9.0

* Set `MinimumOSVersion` to `13.0` for generated Python frameworks.
* iOS and macOS packaging: Python system libraries are put into `python.bundle` to pass App Store verification.
* On macOS, Windows, and Linux, application site packages are copied in an unpacked state to the application bundle to speed up the first launch.
* Pyodide 0.27.2
* Python 3.12.9
* Packaging `--cleanup` option replaced with two separate `--cleanup-app` and `--cleanup-packages` options.
* New packaging options `--cleanup-app-files` and `--cleanup-package-files` to specify a list of globs to exclude files and directories from app and site packages.
* New packaging `--skip-site-packages` option to skip site packages installation for faster re-builds.
* Packaging `--arch` option accepts a list now.

## 0.8.7

* Fixed: `xcframeworks` migration script didn't work for sub-directories.

## 0.8.6

* Added `com.flet.serious_python_android.PythonActivity` holder class with `mActivity` holding a reference to an app MainActivity. Needed for `plyer`.
* Android plugin sets `MAIN_ACTIVITY_HOST_CLASS_NAME` environment variable with the name of activity holder class name (`com.flet.serious_python_android.PythonActivity`).
* Android plugin sets `MAIN_ACTIVITY_CLASS_NAME` environment variable with a class name of an app MainActivity.
* Android plugin sets `ANDROID_NATIVE_LIBRARY_DIR` environment variable with the path to a directory containing app .so libraries. Needed for patching `ctypes.find_library`.
* Changed behavior of `SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS` environment variable that should contain a comma-separated list of packages to allow installation from source distribution.
* Fixed: iOS `site-packages` to `xcframeworks` migration script supports both `library.so` and `library.{something}.so`.

## 0.8.5

* Added Java `loadLibrary` to Android plugin to support `pyjnius` ([#128](https://github.com/flet-dev/serious-python/issues/128)).

## 0.8.4

* Copy `site-packages/flutter` contents to `SERIOUS_PYTHON_FLUTTER_PACKAGES`.
* Added `SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS` variable to allow pip installing from source distributions.

## 0.8.3

* Remove `PYTHONOPTIMIZE=2` to make CFFI work.

## 0.8.2

* Copy `.so` libraries from `{site-packages}/opt` to `jniLibs`.

## 0.8.1

* Remove `--only-binary` when packaging for desktop platforms ([#112](https://github.com/flet-dev/serious-python/issues/112))
* Fixed: only pass string args ('script') if they are not null. ([#77](https://github.com/flet-dev/serious-python/issues/77))
* Fixed: script set as empty string to fix windows build error ([#83](https://github.com/flet-dev/serious-python/issues/83))

## 0.8.0

* New packaging, not based on Kivy and with pre-built binary packages.

## 0.7.1

* Added `namespace` definition to Android Gradle build.
* Bump dependencies.

## 0.7.0

* `runPython()` method to support running Python script.
* Updated `flet_example` to catch program output and errors, `sys.exit()` support.
* `package` command to read dependencies from `pyproject.toml`.

## 0.6.1

* `--exclude` option for `package` command - to exclude directories and files from Python app package.
* Re-create temp Python distributive directory on every run of `package` command.

## 0.6.0

* `--verbose` flag - verbose output.
* `--mobile` flag - (removes `.so`) from app dest archive.
* `--web` flag for packaging for pyodide.
* `--find-links` option for installing pip dependencies from alternative sources (indexes).
* `--dep-mappings` for rewriting `flet` dependency to either `flet-embed` or `flet-pyodide`.
* `--req-deps` for adding required dependencies like `flet-embed` or `flet-pyodide`.
* `--platform` option for use with `sitecustomize.py` to tweak pip to pull platform-specific packages.
* More structured regular output.
* Bump deps versions.

## 0.5.1

* Simplified Python initialization on Android.

## 0.5.0

* Python 3.11.6.

## 0.4.1

* Bumping version after fixing pubspec.yaml.

## 0.4.0

* macOS support.

## 0.3.0

Initial version.
