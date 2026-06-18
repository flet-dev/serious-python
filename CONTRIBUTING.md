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

## Python runtime versions

The supported Python versions, their CPython / Pyodide / dart_bridge details, and
which versions get built are all defined in a single source of truth: the
**`manifest.json`** in [`flet-dev/python-build`](https://github.com/flet-dev/python-build),
published as an asset on each date-keyed (`YYYYMMDD`) release.

serious_python pins one release date (`pythonReleaseDate`) and commits generated
snapshots of that manifest — **never hand-edit these**:

* `src/serious_python/lib/src/python_versions.dart` — read by the CLI commands
* `python_versions.properties` in each platform package — read by the
  Android / Darwin / Linux / Windows build configs

To add or bump a Python / Pyodide / dart_bridge version:

1. Edit `manifest.json` in python-build and cut a new release (run the **Build
   Python Packages** workflow with a `YYYYMMDD` `release_date`).
2. Regenerate the snapshots from the new release:

   ```
   cd src/serious_python
   dart run serious_python:gen_version_tables --release-date <YYYYMMDD>
   ```

   (Omit `--release-date` to re-fetch the currently pinned release.)
3. Commit the regenerated `python_versions.dart` and `python_versions.properties`
   files. CI's **Version tables in sync with manifest** job fails if they drift.

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