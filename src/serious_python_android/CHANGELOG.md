## 4.3.6

* Re-pins the bundled python-build snapshot to **20260720** (`dart_bridge` **1.5.0 → 1.5.1**). 1.5.1 is a Windows-only UTF-8 startup fix (see `serious_python_windows` 4.3.6); the Android runtime is functionally unchanged from 20260719.

## 4.3.4

* Re-pins the bundled python-build snapshot to **20260719** (previously 20260714). The snapshot un-prunes `_pyrepl` on Windows/Linux desktop only; Android already shipped `_pyrepl` (un-pruned in 4.3.2), so these runtimes are byte-identical to 20260714.
* **Android:** fix code edits not taking effect under `flet debug android` — the app kept running the previously-unpacked, stale code after a re-run ([flet-dev/flet#6682](https://github.com/flet-dev/flet/issues/6682)). `prepareApp` copies the app payload out of the APK only when its cache key changes, and the key was `versionName+versionCode`. Since `flet debug` reinstalls the same-version APK on each iteration (`flutter run` does an update install that preserves app data, including the cache marker), the key never changed and re-extraction was skipped. The key now also includes `PackageManager.lastUpdateTime`, which is bumped on every (re)install but stays stable across plain relaunches — so a debug reinstall re-extracts the new code while ordinary relaunches still hit the cache. `flet build apk` was unaffected (fresh/version-bumped install).

## 4.3.3

* Version bump aligning with the `serious_python_*` 4.3.3 release (a Windows build fix). No Android-affecting changes.

## 4.3.2

* **Resolve a package whose `__init__` is itself the native extension.** `_SorefFinder` only probed `<dotted>.soref`, so a package that ships its extension as `<pkg>/__init__.<abi>.so` — e.g. apsw (import name `apsw`), whose relocation marker lands at `apsw/__init__.soref` — was never resolved: `find_spec` returned `None`, the synthesized empty `apsw/__init__.py` won, and `import apsw` yielded an empty module (`AttributeError: module 'apsw' has no attribute 'Connection'`). `find_spec` now falls back to `<dotted>/__init__.soref`, loads the extension under the correct top-level name via `ExtensionFileLoader`, and marks the result a package (with `submodule_search_locations`) so pure-Python submodules (`apsw.ext`, …) still resolve.
* Bump the bundled python-build snapshot to `20260714`, fixing two on-device crashes on Python **3.13/3.14** (3.12 is unaffected; Python/`dart_bridge` versions are unchanged):
  * Apps died with `SIGSYS` at `dlopen()` of `libpython` — before the interpreter even started — on **x86_64/x86/armeabi-v7a**: mimalloc (bundled with CPython since 3.13) reads `/proc/sys/vm/overcommit_memory` during allocator init via a bare `open(2)` syscall, which Android's bionic seccomp policy forbids (only `openat(2)` is allowed). python-build now patches the call to `SYS_openat(AT_FDCWD, …)`. `arm64-v8a` was latently unaffected (no `SYS_open` there, so mimalloc already went through libc `open()` → `openat`), but emulators are typically x86_64.
  * `_pyrepl` is no longer pruned from the bundled stdlib: Python 3.14's `pdb` imports it at module load, so anything importing `pdb` (e.g. pytest's debugging plugin) died with `ModuleNotFoundError: No module named '_pyrepl'`.

## 4.3.1

* Fix `flet build apk --arch <abi>` shipping an **empty `sitepackages.zip`** whenever the selected ABI subset didn't include `arm64-v8a` (e.g. `--arch x86_64`) — the app bundled no Python site-packages at all and the very first dependency import failed at startup. The ABI-common pure-code zips (`sitepackages.zip` / `extract.zip`) were built from a hardcoded primary ABI (`abis.first()`, i.e. `arm64-v8a`); when only other ABIs were staged under `SERIOUS_PYTHON_SITE_PACKAGES`, the primary split task walked a nonexistent directory and silently produced a valid-but-empty zip. The primary ABI is now the first manifest ABI whose site-packages tree was actually staged. If none is staged at all (legitimate when packaging with no requirements), the build falls back to `abis.first()` and logs `sitepackages.zip will be empty` instead of staying silent.

## 4.3.0

* `PYTHONINSPECT=1` is no longer set by any platform implementation. It had no effect on the embedded interpreter, but it leaked into the process environment where any *real* interpreter child (e.g. a serviced multiprocessing worker) would inherit it and hang in interactive mode after its command completed. No functional change on Android, which doesn't support process spawning.
* Bump the bundled python-build snapshot to `20260708` (`dart_bridge` **1.5.0**). The new multiprocessing child-interception exports are present in the runtime but not wired up on Android, which doesn't support process spawning.

## 4.2.1

* Bump the bundled python-build snapshot to `20260701`; aligns with the `serious_python_*` 4.2.1 release. The Android runtimes are byte-identical to `20260630` (the release only rebuilds the iOS runtime).

## 4.2.0

* **`armeabi-v7a` (32-bit ARM) is now bundled for Python 3.13 and 3.14**, not just 3.12. `flet-dev/python-build` `20260630` publishes 32-bit ARM runtimes for those minors (built with `dart_bridge` **1.4.1**), so the per-minor `android_abis` in `python_versions.properties` now include `armeabi-v7a` across the board and `defaultConfig.ndk.abiFilters` + the per-ABI download/copy fan-out pick it up automatically — no Gradle change needed.

## 4.1.1

* Fix app crashing on launch on Android 8.1 and below (API < 28). The `getAppVersion` method-channel handler, called on every startup, used `PackageInfo.getLongVersionCode()` (API 28+) unconditionally. R8 outlines this call into a synthetic class that it can merge with other API 28+ outlines — notably Flutter 3.41's `ImageDecoder`-based image decoder — and invoking that merged class on API < 28 fails verification with `NoClassDefFoundError: android.graphics.ImageDecoder$OnHeaderDecodedListener`. The call is now guarded with a `Build.VERSION.SDK_INT` check, falling back to the deprecated `versionCode` int field on older devices.
* Fix the embedded interpreter crashing on startup on a **non-primary ABI** (e.g. an x86_64 emulator when `arm64-v8a` is the primary ABI) with `ModuleNotFoundError: No module named '_sysconfigdata__android_<arch>-linux-android'`. The ABI-common `stdlib.zip` was built from the primary ABI only, dropping every other ABI's arch-specific `_sysconfigdata__android_<arch>` module — which CPython imports at startup via `sysconfig` (pulled in by `ctypes`). The primary `splitStdlib` task now also harvests each other ABI's `_sysconfigdata__android_<arch>` into `stdlib.zip` (only that arch-specific module, so the generic ABI-identical `_sysconfigdata__linux_` shipped by some versions like 3.12 isn't duplicated).

## 4.1.0

* Run the `extractAsset` / `unzipAsset` / `loadLibrary` method-channel handlers on a background `Executor` (posting the `Result` back on the main looper) instead of inline on the platform main thread. The first-launch asset unpack and the pyjnius native-library load no longer block Android's `Choreographer`, so Flutter's vsync isn't starved and on-screen animations (e.g. a boot/splash spinner) stay smooth while the app starts.
* Ship consumer ProGuard/R8 keep rules (`-keep class com.flet.serious_python_android.** { *; }`) so release (minified) builds don't obfuscate or strip the classes pyjnius resolves by name at runtime. Without them R8 renamed `PythonActivity` and dropped its static `mActivity` field, breaking pyjnius in release builds with `type object 'C.f' has no attribute 'mActivity'` (debug builds were unaffected).
* Version bump aligning with the `serious_python_*` 4.1.0 release.

## 4.0.0

* Ship the app as a *stored* `app.zip` asset in the APK and unpack it once (version-keyed) to `<application-support>/flet/app` on the first launch after install/update, via the new `prepareApp()`. The version-keyed unpack moved out of `run()`; user data in the sibling `<application-support>/data` is preserved across updates.
* Resolve the support dir via `path_provider` `getApplicationSupportDirectory()` (== `context.getFilesDir()`) and drop the custom `getFilesDir` method channel; the payload base moves from `flet/py` to `flet/`.
* Synthesize an empty `__init__.py` for `__init__`-less package directories when building `stdlib.zip`/`sitepackages.zip`, so `zipimport` can import PEP 420 namespace packages (e.g. `flask.sansio`).
* `SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES` entries now support `*`/`?` wildcards matched against the top-level name (e.g. `flask*` also extracts `flask-<version>.dist-info/`).
* Restore `pyjnius` support under the FFI model: re-add the `loadLibrary` method channel and load its JNI helper (`libpyjni.so`) via Java `System.loadLibrary` before the interpreter starts, so the helper's `JNI_OnLoad` captures the `JavaVM` + app ClassLoader (`dart:ffi`'s `dlopen` for `libdart_bridge` never triggers `JNI_OnLoad`). Best-effort — a no-op for apps that don't depend on pyjnius.
* Version bump aligning with the `serious_python_*` 4.0.0 release.

## 3.0.0

* **In-process Python (dart_bridge FFI).** The Python lifecycle now runs through `libdart_bridge.so` (from `flet-dev/dart-bridge` **1.4.0**) instead of a socket transport.
* **Native modules are memory-mapped from the APK — no more `useLegacyPackaging`.** Python extension modules (stdlib `lib-dynload` and site-packages) are relocated into `jniLibs/<abi>/lib<mangled>.so` and loaded directly from the APK by a custom `sys.meta_path` finder that resolves them from `.soref` markers — no extraction to disk, still ABI-split by the Play Store. Pure Python ships in **stored, ABI-common asset zips** read via `zipimport`, so the stdlib is no longer duplicated per ABI. This replaces the previous scheme of zipping stdlib/site-packages into fake `lib*.so` files (which required `useLegacyPackaging`). The dart-bridge Android binary now uses the full CPython API (`PyConfig`) to install the finder before `site` runs. Set **`SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES`** (comma-separated relative paths) to ship path-hungry packages extracted to disk instead.
* **Breaking change:** requires Flutter **3.44.2**. Moves to AGP **8.11.1**, Gradle 8.11.1, `compileSdk` **36**, Java **17**, and the **Kotlin-DSL** Gradle build (`build.gradle.kts`).
* `build.gradle` resolves the Python version from the generated `python_versions.properties` (a snapshot of python-build's `manifest.json`): `SERIOUS_PYTHON_VERSION` selects the version; the full version, build date and `dart_bridge` version derive from the table, with `SERIOUS_PYTHON_FULL_VERSION` / `SERIOUS_PYTHON_BUILD_DATE` / `DART_BRIDGE_VERSION` left as escape hatches. Downloads continue to use python-build's date-keyed release scheme.
* Drop the `x86` (32-bit Intel) ABI — Flutter no longer produces it. ABIs are `arm64-v8a` + `x86_64` (plus `armeabi-v7a` on Python 3.12).
* Remove the scaffold `getPlatformVersion` method.

## 2.0.0

* **Breaking change:** default bundled Python version is now 3.14 (was 3.12). Apps built without an explicit `SERIOUS_PYTHON_VERSION` env var pull the 3.14 python-build distribution and ship `libpython3.14.so`. Set `SERIOUS_PYTHON_VERSION=3.12` (typically threaded through `flet build`) to preserve the previous default.
* Multi-version Python support. `python_version` in `android/build.gradle` reads from `SERIOUS_PYTHON_VERSION` and drives the `flet-dev/python-build` download URL.
* The Dart runtime no longer hardcodes `libpython3.12.so` — it scans `nativeLibraryDir` for `libpython3.*.so` so whichever libpython the plugin bundled is loaded automatically.
* `abiFilters` now branches on `python_version`: keep `armeabi-v7a` for 3.12, restrict to `arm64-v8a` + `x86_64` for 3.13+ (python-build dropped 32-bit Android per PEP 738).

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

* macOS, Windows and Linux support.

## 0.3.0

Initial version.
