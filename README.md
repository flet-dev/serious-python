# serious_python

A cross-platform plugin for adding embedded Python runtime to your Flutter apps.

Serious Python embeds Python runtime into a mobile or desktop Flutter app to run a Python program on a background, without blocking UI. Processing files, working with SQLite databases, calling REST APIs, image processing, ML, AI and other heavy lifting tasks can be conveniently done in Python and run directly on a mobile device.

Build app backend service in Python and host it inside a Flutter app. Flutter app is not directly calling Python functions or modules, but instead communicating with Python environmnent via some API provided by a Python program, such as: REST API, sockets, SQLite database or files.

Serious Python is part of [Flet](https://flet.dev) project - the fastest way to build Flutter apps in Python. The motivation for building Serious Python was having a re-usable easy-to-use plugin, maintained and supported, to run real-world Python apps, not just "1+2" or "hello world" examples, on iOS or Android devices and hence the name "Serious Python".

## Platform Support

| iOS     |   Android    |
| :-----: | :----------: |
|   ✅    |       ✅      |

### Python versions

iOS version of plugin is based on [Kivy toolchain](https://github.com/kivy/kivy-ios) and currently uses Python 3.10.10.

Android version of plugin is based on [Kivy python-for-android](https://github.com/kivy/python-for-android) and currently uses Python 3.10.10.

## Usage

Zip your Python app into `app.zip`, copy to `app` (or any other) directory in the root of your Flutter app and add it as an asset to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - app/app.zip
```

Import Serious Python package into your app:

`import 'package:serious_python/serious_python.dart';`

The plugin is built against iOS 12.0, so you might need to update iOS version in `ios/Podfile`:

```bash
# Uncomment this line to define a global platform for your project
platform :ios, '12.0'
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

### Packaging Python app

To simplify the packaging of your Python app Serious Python provides a CLI which can be run with the following command:

```
dart run serious_python:main
```

There is `package` command which takes a directory with Python app as the first argument. The command must be run in Flutter app root directory, where `pubspec.yaml` is located. The path could be either relative or an absolute:

```
dart run serious_python:main package app/src
```

By default, the command creates `app/app.zip` asset, but you can change its path/name with `--asset` argument:

```
dart run serious_python:main package --asset assets/myapp.zip app/src
```

If there is `requirements.txt` or `pyproject.toml` in the root of source directory `package` command will try to install dependencies to `__pypackages__` in the root of destination archive.

Make sure generated asset is added to `pubspec.yaml`.

## Python app structure

By default, embedded Python program is run in a separate thread, to avoid UI blocking. Your Flutter app is not supposed to directly call Python functions or modules, but instead it should communicate via some API provided by a Python app, such as: REST API, sockets, SQLite database, files, etc.

To constantly run on background a Python program must be blocking, for example a [Flask app](example/flask_example) listening on `8000` port, or you can start your long-running computations in `threading.Thread` and use `threading.Event` to prevent program from exiting.

Synchronous execution of Python program is also supported with `sync: true` parameter to `SeriousPython.run()` method. For example, it could be a utility program doing some preperations, etc. Just make sure it's either very short or run in a Dart isolate to avoid blocking UI.

## Supported Python packages

All "pure" Python packages are supported. These are packages that implemented in Python only, without native extensions written in C, Rust or other low-level language.

For iOS: packages with native extensions having a [recipe](https://github.com/kivy/kivy-ios/tree/master/kivy_ios/recipes) are supported. To use these packages you need to build a custom Python distributive for iOS (see below).

## Building custom Python distributive

### iOS

TBD

## Examples

[Python REPL with Flask backend](example/flask_example).

[Flet app](example/flet_example).

## Future plans

- Adding Android support.
- Embeddable Python for desktop Flutter apps (in the order of priority): macOS, Windows, Linux.