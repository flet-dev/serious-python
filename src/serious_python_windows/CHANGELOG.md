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

* Initial release of `serious_python_windows` package.