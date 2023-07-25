# Contributing to `serious_python`

## Releasing a new version

Bump version in:

* `pubspec.yaml`
* `android/build.gradle`
* `ios/serious_python.podspec`

Bump `serious_python` dependency version with `flutter pub get` in example lock files:

* `example/flet_example/pubspec.lock`
* `example/flask_example/pubspec.lock`