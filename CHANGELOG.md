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