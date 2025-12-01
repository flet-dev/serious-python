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