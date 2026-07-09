## 4.3.0

* **Desktop multiprocessing support** ([flet-dev/flet#4283](https://github.com/flet-dev/flet/issues/4283)). `dart_bridge` **1.5.0** adds `serious_python_is_mp_invocation` / `serious_python_main` (+ `_w` wide-char variants on Windows): host apps call them first thing in `main` to detect CPython child command lines (`--multiprocessing-fork`, `-c "from multiprocessing..."` — spawn workers, the resource tracker, and the forkserver) and service them as a plain headless interpreter (`Py_Main`/`Py_BytesMain`, stable ABI) instead of re-launching the GUI. The exports rely on the `PYTHONHOME`/`PYTHONPATH` the parent already stamped process-wide.
* `PYTHONINSPECT=1` is no longer set by any platform implementation. It had no effect on the embedded interpreter, but it leaked into the process environment where any *real* interpreter child (e.g. a serviced multiprocessing worker) would inherit it and hang in interactive mode after its command completed.
* Bump the bundled python-build snapshot to `20260708`, which delivers `dart_bridge` **1.5.0**; Pyodide for 3.14 bumped **314.0.1 → 314.0.2**. Bundled Python versions are unchanged from 4.2.1 (**3.12.13 / 3.13.14 / 3.14.6**).
* **Windows:** fix `flet build windows` failing with `file INSTALL cannot find "C:/WINDOWS/System32/vcruntime140_1.dll"` for users who build with VS Build Tools rather than full Visual Studio (a WOW64 file-system-redirection issue with the bundled 32-bit cmake). See `serious_python_windows` 4.3.0.

## 4.2.1

* **iOS/macOS:** ctypes packages that ship plain `.dylib` shared libraries (e.g. `llama-cpp-python`'s `libllama` / `libggml`) now load on the **iOS simulator**. Such `.dylib`s are now packaged as per-slice xcframeworks (previously only `.so` C-extensions were), so they carry a simulator slice instead of shipping the device build and failing `dlopen` with `incompatible platform (have 'iOS', need 'iOS-simulator')`; their install-name is preserved so multi-lib packages still resolve their sibling libs. See `serious_python_darwin` 4.2.1.
* **iOS:** the `_multiprocessing` extension is now built into the runtime (importable, not spawnable) via `flet-dev/python-build` `20260701`. Bundled Python versions are unchanged from 4.2.0 (**3.12.13 / 3.13.14 / 3.14.6**).

## 4.2.0

* **Android:** `armeabi-v7a` (32-bit ARM) is now bundled for Python **3.13** and **3.14**, not just 3.12 — `flet-dev/python-build` `20260630` publishes 32-bit ARM runtimes for those minors (built with `dart_bridge` **1.4.1**). The `package` command's hardcoded "3.12-only" `armeabi-v7a` skip is replaced by a manifest-driven check against each minor's `PythonRelease.androidAbis`, so the wheel fan-out (and the Android plugin's `abiFilters`) follow whatever python-build publishes per minor.
* Bundle **3.12.13 / 3.13.14 / 3.14.6** (python-build `20260630`; CPython-standalone `20260623`); Pyodide **0.27.7 / 0.29.4 / 314.0.1** (3.14 bumped 314.0.0 → 314.0.1).

## 4.1.1

* **Android:** fix two startup crashes — apps crashing on launch on Android 8.1 and below (API < 28) due to an unguarded `getLongVersionCode()` call, and the interpreter failing to start on a non-primary ABI (e.g. an x86_64 emulator) with `ModuleNotFoundError: No module named '_sysconfigdata__android_<arch>-linux-android'`. See `serious_python_android` 4.1.1.

## 4.1.0

* **Android:** run first-launch asset unpacking and native library loading off the platform main thread so they no longer block vsync — boot-time animations (e.g. a splash / boot screen spinner) stay smooth while the app starts. Also ship consumer ProGuard rules that keep the pyjnius bootstrap classes, fixing pyjnius in release (minified) Android builds. See `serious_python_android` 4.1.0.

## 4.0.0

* **App packaging lifted into serious_python.** Your Python app now ships **unpacked inside the application bundle**, next to the Python stdlib and site-packages, on macOS / iOS / Windows / Linux — no first-launch `app.zip` extraction. On **Android** the app ships as a *stored* `app.zip` asset inside the APK and is unpacked once (version-keyed) to the app-support files dir on the first launch after an install/update, like the existing `extract.zip`. Web (Pyodide) is unchanged. The `package` command stages the processed app into **`SERIOUS_PYTHON_APP`** (symmetric with `SERIOUS_PYTHON_SITE_PACKAGES`); each platform's native build copies it into the bundle (Android zips it as a stored asset).
* **New `SeriousPython.prepareApp()`** — materializes the app (Android first-launch unpack) and returns the directory containing its entry point. **`SeriousPython.run()` now takes no `assetPath` argument** (it resolves the app via `prepareApp()`), sets the current directory to a writable per-app data dir (`<application-support>/data`) — not the read-only bundle — so relative file writes / SQLite work, and runs `main.pyc`/`main.py` (or `appFileName`).
* **Breaking change:** the `app.zip` asset convention and the runtime zip-extraction API are removed — `SeriousPython.run("app/app.zip")`, `extractAssetZip`, and `extractFileZip` no longer exist. Repackage with `dart run serious_python:main package <app> -p <platform>` and call `SeriousPython.run()` with no arguments.
* **Android:** the runtime payload moved to `<application-support>/flet/{app, stdlib.zip, sitepackages.zip, extract/}` (resolved via `getApplicationSupportDirectory()`; the custom `getFilesDir` method channel is dropped). User data in the sibling `<application-support>/data` survives app updates.
* **Swift Package Manager (darwin) staging in the `package` command — on by default.** For iOS/macOS the `package` command runs the host-side equivalent of the podspec `prepare_command` (which SPM has no hook for) by resolving `serious_python_darwin`'s `darwin/` dir (`SERIOUS_PYTHON_DARWIN_DIR` override, else the project's `package_config.json`), invoking `prepare_spm.sh`, and writing the `SP_NATIVE_SET` cache-bust key to `build/.serious_python_spm_key` (overridable via `SERIOUS_PYTHON_SPM_KEY_FILE`) for the caller to export into the `flutter build` environment. SPM is Flutter's default darwin integration since 3.44, so this happens by default — set **`SERIOUS_PYTHON_DARWIN_SPM`** to a falsy value (`0`/`false`/`no`/`off`) to opt out and build with CocoaPods (the podspec stages then). See `serious_python_darwin` 4.0.0.

## 3.0.0

* **New in-process transport (dart_bridge FFI).** `SeriousPython.run` can now run the embedded interpreter **in-process** through the `dart_bridge` FFI bridge instead of talking to it over a socket. The Python lifecycle (initialize / run / teardown) is absorbed into the `dart_bridge` native library on every platform — `dart_bridge.xcframework` (iOS/macOS), `libdart_bridge.so` (Android/Linux), and `dart_bridge.dll` / `dart_bridge.pyd` (Windows) — and a new `PythonBridge` API exposes a MsgPack control channel plus dedicated binary data channels between Dart and Python. See the `bridge_example` app. The bundled `dart_bridge` is **1.4.0**.
* **Android native packaging — memory-mapped from the APK.** Python extension modules are relocated into `jniLibs` and loaded **directly from the APK** (mmap, no extraction) by a custom importer that resolves them from `.soref` markers; pure Python ships in stored, ABI-common asset zips read via `zipimport` (no per-ABI duplication). Apps no longer need `useLegacyPackaging` / `keepDebugSymbols` — the brittle per-app packaging config is gone. Set **`SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES`** (comma-separated relative paths) to ship path-hungry packages extracted to disk. The dart-bridge Android binary uses the full CPython API (`PyConfig`) to install the importer before `site` runs.
* **Breaking change:** requires Flutter **3.44.2** / Dart 3.12+. The Android plugin moves to AGP **8.11.1**, `compileSdk` **36**, Java **17**, and the Kotlin-DSL Gradle build (`build.gradle.kts`).
* Python runtime versions are now a committed snapshot of `flet-dev/python-build`'s date-keyed `manifest.json`, generated by `dart run serious_python:gen_version_tables`. **`SERIOUS_PYTHON_VERSION`** (short, e.g. `3.14`) is the single input — the full CPython version, python-build release date, Pyodide version + platform tag, and `dart_bridge` version all derive from it. `SERIOUS_PYTHON_FULL_VERSION`, `SERIOUS_PYTHON_BUILD_DATE`, and `DART_BRIDGE_VERSION` remain as rarely-needed escape hatches. The native build configs (Android `build.gradle`, Darwin podspec, Linux/Windows `CMakeLists.txt`) read the generated `python_versions.properties`, and a CI job fails if the snapshots drift from the manifest. This replaces the per-config hardcoded defaults and the `flet build`-exported `SERIOUS_PYTHON_FULL_VERSION` / `SERIOUS_PYTHON_BUILD_DATE` introduced in 2.0.0.
* Bundle **3.12.13 / 3.13.14 / 3.14.6** (python-build `20260614`); Pyodide **0.27.7 / 0.29.4 / 314.0.0** (314.0.0 GA, up from the 314.0.0a2 in 2.0.0).
* Add **`dart run serious_python:main version [--json]`** — prints the serious_python version, the pinned python-build release, and the supported Python / Pyodide / dart_bridge matrix.
* The embedded Darwin runtime re-extracts when the selected Python version changes (a version marker guards `dist_ios` / `dist_macos`), so a clean build after switching `--python-version` can't mix C-extension ABIs (`bad magic number` / `unknown slot ID`).
* Cache downloaded Python distributions and `dart_bridge` artifacts under `$FLET_CACHE_DIR` (default `~/.flet/cache`) across all platforms.
* Remove the scaffold `getPlatformVersion` method from the platform plugins.
* Drop the `x86` (32-bit Intel) Android ABI — Flutter no longer produces it. Android builds target `arm64-v8a` + `x86_64` (plus `armeabi-v7a` on Python 3.12); the `x86` wheel platform-tag entry and the Android packaging rules referencing it are removed.
* Android ABI list now reads from python-build's manifest (per-minor `android_abis`, surfaced as `<short>.android_abis` in `python_versions.properties` and `PythonRelease.androidAbis` in the generated Dart) instead of the hardcoded `if pythonVersion == "3.12"` branch in `serious_python_android/android/build.gradle.kts`. Drives both `defaultConfig.ndk.abiFilters` and the per-ABI download/copy fan-out; adding a future minor only needs the one-line manifest edit.
* **Breaking change:** the `configure` command (and the bare in-place version-switching machinery, including `stageDarwinRuntime`) is removed. Switching the bundled Python version between builds is now handled by a clean rebuild — `flet build` wipes its build dir on a version change, and the Darwin `dist_ios` / `dist_macos` version marker re-extracts the runtime — so a separate `serious_python configure` step is no longer needed.
* **Bug fix:** the Pyodide 0.29 wheel platform tag for the 3.13 row was `pyodide-2025.0-wasm32`, but Pyodide publishes 0.29 wheels under `pyemscripten_2025_0_wasm32`; corrected to `pyemscripten-2025.0-wasm32` so `flet build web --python-version 3.13` matches native wheels.

## 2.0.0

* **Breaking change:** the `package` command's default Python is now the latest supported stable (3.14), up from the previously implicit 3.12. Scripts that ran `dart run serious_python:main package …` without `--python-version` will now download CPython 3.14, install 3.14 wheels, and use the matching Pyodide / Android platform tags. Pin explicitly with `--python-version 3.12` (or `SERIOUS_PYTHON_VERSION=3.12`) to preserve the old behavior.
* **Breaking change:** Android `sysconfig.get_platform()` tag format changed from `android-24-arm64-v8a` to `android-24-arm64_v8a` (and similarly for `armeabi-v7a`). The emitted wheel tag (`android_24_arm64_v8a`) is unchanged, but anything reading the raw `sysconfig.get_platform()` string from `sitecustomize.py` should switch separators.
* **Breaking change:** Windows host arch identifier dropped the `-shared` suffix (`x86_64-pc-windows-msvc-shared` → `x86_64-pc-windows-msvc`); follows astral-sh/python-build-standalone, which only publishes the combined (already shared) `install_only_stripped` build.
* Multi-version Python support. The `package` command accepts `--python-version` (or `SERIOUS_PYTHON_VERSION` env var) to select between Python 3.12 / 3.13 / 3.14. The matching CPython-standalone build, Pyodide release, and Emscripten wheel platform tag are looked up from a new `_pythonReleases` table. Adding a future pre-release line (e.g. 3.15 beta) is a one-row append with `prerelease: true`; the Flet CLI uses that flag to keep open-ended `requires-python` specifiers (`>=3.14`) on stable, while still letting `--python-version 3.15` or `==3.15.*` opt in.
* The Emscripten pip platform tag is now derived per Python release (e.g. `pyodide-2024.0-wasm32` for 0.27.7, `pyemscripten-2026.0-wasm32` for 314.0.0a2), via a `pyodide_platform_tag` field in the version registry. The previous static `pyodide-2024.0-wasm32` entry in `platforms["Emscripten"]` has been removed.
* `sitecustomize.py` now shims `platform.android_ver` so the new pip / packaging that ships with python-build-standalone 20260602+ can compute Android wheel tags on Python 3.12 hosts (where `android_ver` didn't exist) and on Python 3.13+ hosts (where it returns `api_level=0` off-device).
* Skip 32-bit Android ABIs (`armeabi-v7a`, `x86`) when Python ≥ 3.13 — PEP 738 dropped 32-bit Android support, and `flet-dev/python-build` no longer publishes those runtimes for those versions.

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

* Not based on Kivy!
* Fast packaging uses pre-built Python binary packages hosted on https://pypi.flet.dev and https://pypi.org. If a binary package for specific platform/arch is not found the packaging process does not make an attempt to compile it, but just exits with a meaningful error.
* To package for iOS and Android developer should set `SERIOUS_PYTHON_SITE_PACKAGES` environment variable with a path to a temp directory for installed app packages. The contents of that directory is embedded into app bundle during app compilation. For macOS, Linux and Windows app packages are installed into `__pypackages__` inside app package asset zip.
* Packaging command is not looking for `requirements.txt` or `pyproject.toml` anymore, but all requirements should be passed explicitly via `--requirements` option. The value of `--requirements` option is passed "as is" to `pip` command. For example, `--requirements flet,numpy==2.1.1` install two requirements directly, or `--requirements -r,requirements.txt` installs deps from a file.
* MacOS packaging includes Python binaries for both `arm64` and `x86_64` architectures. Can limit to only one architecture with `--arch` option.
* New options to enable compilation and cleanup of app and packages .py files: `--compile-app`, `--compile-packages` and `--cleanup`.
* Packaging for `web` is no longer relied on a HTML document with links, but spawns its own PyPI-compatible server with links to Pyodide packages. 
* Build python distributive is cached in Flutter's `build` directory, not temp, to avoid re-downloading on consequent re-packages.
* Web builds updated to Pyodide 0.26.2.
* Packages for iOS and Android are built with [Mobile Forge](https://github.com/flet-dev/mobile-forge).
* Python for all platforms is built with [flet-dev/python-build](https://github.com/flet-dev/python-build/) and [this CI job](https://ci.appveyor.com/project/flet-dev/python-build). Python distros for Dart and Mobile Forge uploaded to [releases](https://github.com/flet-dev/python-build/releases).

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

* Python 3.11.6 for all platforms.

## 0.4.1

* Bumping version after fixing pubspec.yaml.

## 0.4.0

* macOS, Windows and Linux support.
* Support for custom Python libraries in Android and iOS apps.

## 0.3.1

* Set Flutter SDK requirements to remove publishing warnings.

## 0.3.0

* `serious_python` all-in-one package refactored to a federated plug-in with multiple endorsed packages.

## 0.2.4

* Fix _Py_HashRandomization_Init error on Windows.
* Reliably re-download Python executable.

## 0.2.3

* Android fixes to make it work on some devices when installed via Play Store.

## 0.2.2

* Exclude `x86` from supported ABIs.
* Fixed: Packaging python app using the packaging command raising an error on windows ([#8](https://github.com/flet-dev/serious-python/issues/8)).

## 0.2.1

* Fix iOS pod.

## 0.2.0

* Android support.

## 0.1.5

* SeriousPython.run() should be split into two methods to return temp dir with unpacked python app ([#6](https://github.com/flet-dev/serious-python/issues/6)).

## 0.1.4

* Bump `.podspec` version.

## 0.1.3

* Add app's path to `PYTHONPATH`.
* Compile Python app to a bytecode.
* Compile Python system standard libraries to a bytecode.

## 0.1.2

* Package dist `site-packages` to a zip, so publishing to App Store doesn't fail.

## 0.1.1

* Fixed issue with setting current directory on Python start.
* Added `--pre` flag to `serious_python:main` CLI.
* Added Flet example.
* Hid internal implementation behind `src` dir.

## 0.1.0

* Initial release of `serious_python` with iOS support.
