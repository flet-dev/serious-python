# Contributing to `serious_python`

## Releasing a new version

Bump version in:

* `pubspec.yaml`
* `src/serious_python_android/android/build.gradle`
* `src/serious_python_darwin/ios/serious_python_darwin.podspec`

Bump `serious_python` dependency version with `flutter pub get` in example lock files:

* `src/serious_python/example/flet_example/pubspec.lock`
* `src/serious_python/example/flask_example/pubspec.lock`
* `src/serious_python/example/run_example/pubspec.lock`

Update `CHANGELOG.md`.

## Getting token for automatic publishing to pub.dev

Token locations on different OSes: https://stackoverflow.com/a/70487480/1435891

Login to pub.dev:

```
flutter pub login
```

Encode token to base64:

```
cat $HOME/Library/Application\ Support/dart/pub-credentials.json | base64
```