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