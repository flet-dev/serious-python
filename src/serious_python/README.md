# serious_python

A cross-platform plugin for adding embedded Python runtime to your Flutter apps.

Serious Python embeds Python runtime into a mobile or desktop Flutter app to run a Python program on a background, without blocking UI. Processing files, working with SQLite databases, calling REST APIs, image processing, ML, AI and other heavy lifting tasks can be conveniently done in Python and run directly on a mobile device.

Build app backend service in Python and host it inside a Flutter app. Flutter app is not directly calling Python functions or modules, but instead communicating with Python environment via some API provided by a Python program, such as: REST API, sockets, SQLite database or files.

Serious Python is part of [Flet](https://flet.dev) project - the fastest way to build multi-platform apps in Python. The motivation for building Serious Python was having a re-usable easy-to-use plugin, maintained and supported, to run real-world Python apps, not just "1+2" or "hello world" examples, on iOS or Android devices and hence the name "Serious Python".

## Platform Support

| iOS     |   Android    |   macOS    |   Linux    |   Windows    |
| :-----: | :----------: | :---------: | :-------: | :----------: |
|   ✅    |       ✅      |       ✅    |     ✅     |      ✅      |

### Python versions

The plugin can bundle one of several Python releases per build, selected via
the `--python-version X.Y` flag of `serious_python:main package` (or the
`SERIOUS_PYTHON_VERSION` env var picked up by the Android/Darwin/Linux/Windows
plugin build scripts). Defaults to the latest supported version when nothing
is specified.

| Short | CPython runtime | Pyodide (web) | Pyodide wheel platform tag       |
| ----- | --------------- | ------------- | -------------------------------- |
| 3.12  | 3.12.13         | 0.27.7        | `pyodide-2024.0-wasm32`           |
| 3.13  | 3.13.14         | 0.29.4        | `pyemscripten-2025.0-wasm32`      |
| 3.14  | 3.14.6          | 314.0.0       | `pyemscripten-2026.0-wasm32`      |

The default is the latest stable row (currently **3.14**) when neither
`--python-version` nor `SERIOUS_PYTHON_VERSION` is set. When running through
[`flet build`](https://flet.dev/docs/publish/), the same resolution is
applied to `[project].requires-python` in your `pyproject.toml`, so most
users never need to touch this flag directly.

`SERIOUS_PYTHON_VERSION` (short, e.g. `3.14`) is the only input most users
need to set. When `flet build` invokes the platform plugins it also exports
`SERIOUS_PYTHON_FULL_VERSION` (e.g. `3.14.6`) and `SERIOUS_PYTHON_BUILD_DATE`
(e.g. `20260611` — the `flet-dev/python-build` release tag); the plugin build
scripts pick them up automatically and combine them into the
`…/<date>/python-*-<full>-*` download URLs.

Source of truth: the `_pythonReleases` map in
[`bin/package_command.dart`](bin/package_command.dart) (Dart side) and
`flet_cli/utils/python_versions.py` (Python side). Adding a new short version
means appending a row to both. Pre-release CPython lines (e.g. 3.15) can be
listed with `prerelease: true` so they're opt-in via explicit
`--python-version 3.15` (or `requires-python = "==3.15.*"`) without becoming
the auto-resolved default.

## Usage

Zip your Python app into `app.zip`, copy to `app` (or any other) directory in the root of your Flutter app and add it as an asset to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - app/app.zip
```

Import Serious Python package into your app:

`import 'package:serious_python/serious_python.dart';`

The plugin is built against iOS 13.0, so you might need to update iOS version in `ios/Podfile`:

```bash
# Uncomment this line to define a global platform for your project
platform :ios, '13.0'
```

Create an instance of `SeriousPython` class and call its `run()` method:

```dart
SeriousPython.run("app/app.zip");
```

When the app starts the archive is unpacked to a temporary directory and Serious Python plugin will try to run `main.py` in the root of the archive. Current directory is changed to a temporary directory.

If your Python app has a different entry point it could be specified with `appFileName` parameter:

```dart
SeriousPython.run("app/app.zip", appFileName: "my_app.py");
```

You can pass a map with environment variables that should be available in your Python program:

```dart
SeriousPython.run("app/app.zip",
    appFileName: "my_app.py",
    environmentVariables: {"a": "1", "b": "2"});
```

By default, Serious Python expects Python dependencies installed into `__pypackages__` directory in the root of app directory. You can add additional paths to look for 3rd-party packages using `modulePaths` parameter:

```dart
SeriousPython.run("app/app.zip",
    appFileName: "my_app.py",
    modulePaths: ["/absolute/path/to/my/site-packages"]);
```

By default the Python program runs in a background thread so the Flutter UI stays responsive. Pass `sync: true` to run it on the calling thread instead — useful for short utility programs or when calling from a Dart isolate; long-running synchronous programs will freeze the UI on the main isolate:

```dart
SeriousPython.run("app/app.zip", sync: true);
```

### Packaging Python app

> **Tip:** `serious_python` is also driven automatically by [`flet build`](https://flet.dev/docs/publish/), which threads `--python-version` and friends through for you. The instructions below cover direct standalone usage for non-Flet Flutter apps.

To simplify the packaging of your Python app Serious Python provides a CLI which can be run with the following command:

```
dart run serious_python:main
```

There is `package` command which takes a directory with Python app as the first argument. The command must be run in Flutter app root directory, where `pubspec.yaml` is located. The path could be either relative or an absolute.

To package Python files for the specific platform:

```
dart run serious_python:main package app/src -p {platform}
```

where `{platform}` can be one of the following: `Android`, `iOS`, `Darwin`, `Windows`, `Linux` or `Emscripten`. (`Darwin` covers both macOS apps and is the value used internally by `platform.system()` in the bundled Python; it is **not** spelled `macOS`.)

By default, the command creates `app/app.zip` asset, but you can change its path/name with `--asset` argument:

```
dart run serious_python:main package --asset assets/myapp.zip app/src -p {platform}
```

#### Selecting a Python version

Pick which CPython line to bundle with `--python-version` (or set
`SERIOUS_PYTHON_VERSION` in the build environment):

```
dart run serious_python:main package app/src -p Android --python-version 3.13 -r flet
```

Supported short versions today are **3.12**, **3.13**, **3.14**; the default
is the latest stable. The same env var (`SERIOUS_PYTHON_VERSION`) is also
read by each platform plugin's build script (`build.gradle`, the
`serious_python_darwin` podspec, the Linux/Windows `CMakeLists.txt`) when
`flutter build` runs later, so a single `export` covers both the packaging
phase and the Flutter build phase. See the [Python versions](#python-versions)
table above for the matching CPython and Pyodide releases.

#### Installing requirements

Python app dependencies are installed with the `--requirements` option (alias `-r`). The value is passed verbatim to `pip`, so any flag pip accepts works. Pass each dependency as its own option to support specifiers that contain commas:

```
dart run serious_python:main package app/src -p Darwin \
    -r flet -r 'pandas>=2.2,<3' -r numpy==2.1.1
```

To install from a `requirements.txt` file, pass `-r` three times (twice for pip's own `-r` flag, once more for the file path) so the Dart CLI hands the literal `-r requirements.txt` invocation to pip:

```
dart run serious_python:main package app/src -p iOS \
    -r -r -r app/src/requirements.txt
```

> The comma-separated form (`--requirements flet,numpy==2.1.1`) was removed in **0.9.2** as a breaking change so dependency specifiers containing `,` (like `pandas>=2.2,<3`) can be expressed; use the per-option form shown above instead.

To package for `iOS` and `Android` platforms developer should set `SERIOUS_PYTHON_SITE_PACKAGES` environment variable with a path to a temp directory for installed app packages. The contents of that directory is embedded into app bundle during app compilation.

For example:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p iOS -r -r -r app/src/requirements.txt
```

For macOS, Linux and Windows app packages are installed into `__pypackages__` inside app package asset zip.

Make sure generated asset is added to `pubspec.yaml`.

## Python app structure

By default, embedded Python program is run in a separate thread, to avoid UI blocking. Your Flutter app is not supposed to directly call Python functions or modules, but instead it should communicate via some API provided by a Python app, such as: REST API, sockets, SQLite database, files, etc.

To constantly run on background a Python program must be blocking, for example a [Flask app](example/flask_example) listening on `8000` port, or you can start your long-running computations in `threading.Thread` and use `threading.Event` to prevent program from exiting.

Synchronous execution of Python program is also supported with `sync: true` parameter to `SeriousPython.run()` method. For example, it could be a utility program doing some preperations, etc. Just make sure it's either very short or run in a Dart isolate to avoid blocking UI.

## Supported Python packages

All "pure" Python packages are supported. These are packages that implemented in Python only, without native extensions written in C, Rust or other low-level language.

The following **iOS** and **Android** packages are supported: https://pypi.flet.dev

The following **Pyodide** packages are supported: https://pyodide.org/en/stable/usage/packages-in-pyodide.html

Additional Python binary packages for iOS and Android can be built with adding a new recipe to [Mobile Forge](https://github.com/flet-dev/mobile-forge) project.

Request additional packages for iOS and Android on [Flet Discussions - Packages](https://github.com/flet-dev/flet/discussions/categories/packages).

## Platform notes

### Build matrix

The following matrix shows which platform you should build on to target specific platforms:

| Build on / Target  |   iOS   |   Android   |   macOS    |   Linux    |   Windows    |    Web    |
| :----------------: | :-----: | :---------: | :--------: | :--------: | :----------: | :--------: |
| macOS              |   ✅    |       ✅     |      ✅    |           |              |     ✅     |
| Windows            |         |       ✅     |            |  ✅ (WSL)  |      ✅      |     ✅     |
| Linux              |         |       ✅     |            |     ✅     |              |     ✅     |


### macOS

macOS 10.15 (Catalina) is the minimal supported vesion of macOS.

You have to update your Flutter app's `macos/Podfile` to have this line at the very top:

```ruby
platform :osx, '10.15'
```

Also, make sure `macos/Runner.xcodeproj/project.pbxproj` contains:

```objc
MACOSX_DEPLOYMENT_TARGET = 10.15;
```

### Android

To make `serious_python` work in your own Android app:

If you build an App Bundle Edit `android/gradle.properties` and add the flag:

```
android.bundle.enableUncompressedNativeLibs=false
```

If you build an APK Make sure `android/app/src/AndroidManifest.xml` has `android:extractNativeLibs="true"` in the `<application>` tag.

For more information, see the [public issue](https://issuetracker.google.com/issues/147096055).

## Troubleshooting

### Detailed logging

Use `--verbose` flag to enabled detailed logging:

```
dart run serious_python:main package app/src -p Darwin --verbose
```

## Examples

[Python REPL with Flask backend](example/flask_example).

[Flet app](example/flet_example).

[Run Python app](example/run_example).
