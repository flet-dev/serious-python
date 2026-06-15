## 3.0.0

* **In-process Python (dart_bridge FFI).** The Python lifecycle is absorbed into `libdart_bridge.so` (from `flet-dev/dart-bridge` **1.2.3**, `DT_RPATH $ORIGIN`) instead of a socket transport.
* **Breaking change:** requires Flutter **3.44.2**.
* `CMakeLists.txt` resolves the Python version from the generated `python_versions.properties` (a snapshot of python-build's `manifest.json`): `SERIOUS_PYTHON_VERSION` selects the version; the full version and build date derive from the table, with `SERIOUS_PYTHON_FULL_VERSION` / `SERIOUS_PYTHON_BUILD_DATE` left as escape hatches. Downloads continue to use python-build's date-keyed release scheme.
* Remove the scaffold `getPlatformVersion` method.

## 2.0.0

* **Breaking change:** default bundled Python version is now 3.14 (was 3.12). The plugin downloads `python-linux-dart-3.14-<arch>.tar.gz` from `flet-dev/python-build` and bundles `libpython3.14.so.1.0` unless `SERIOUS_PYTHON_VERSION=3.12` is set in the build environment.
* Multi-version Python support. `PYTHON_VERSION` in `linux/CMakeLists.txt` reads from `SERIOUS_PYTHON_VERSION`, and all `python3.12` / `libpython3.12.so.1.0` / `lib/python3.12` paths are derived from it. The plugin source receives the version via a `SERIOUS_PYTHON_VERSION` compile-time macro so the runtime module path matches the bundled distro.

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

* Initial release of `serious_python_linux` package.
