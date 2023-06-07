# serious_python

Embedded Python runtime for Flutter apps.

## Platform Support

| iOS     |   Android   |
| :-----: | :----------: |
|   ✅    |  Coming soon |

# Usage

Import Serious Python package into your app:

`import 'package:serious_python/serious_python.dart';`

The plugin is built against iOS 12.0, so you might need to update iOS version in `ios/Podfile`:

```
# Uncomment this line to define a global platform for your project
platform :ios, '12.0'
```

Create an instance of `SeriousPython` class and call its `run()` method:

```dart
SeriousPython().run("app/app.zip");
```

`app/app.zip` is a path to asset archive with your Python app.

Add an asset path to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - app/app.zip
```

When the app starts the archive is unpacked to a temporary directory and Serious Python plugin will try to run `main.py` in the root of the archive. Current directory is changed to a temporary directory.

If your Python app has a different entry point it could be specified with `appFileName` parameter:

```dart
SeriousPython().run("app/app.zip", appFileName: "my_app.py");
```

You can pass a map with environment variables that should be available in your Python program:

```dart
SeriousPython().run("app/app.zip",
    appFileName: "my_app.py",
    environmentVariables: {"a": "1", "b": "2"});
```

By default, Serious Python expects Python dependencies installed into `__pypackages__` directory in the root of app directory. You can add additional paths to look for 3rd-party packages using `modulePaths` parameter:

```dart
SeriousPython().run("app/app.zip",
    appFileName: "my_app.py",
    modulePaths: ["/absolute/path/to/my/site-packages"]);
```

## Packaging Python app

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

TBD

# FAQ

## Which Python version does plugin embed?

iOS version of plugin is based on [Kivy toolchain](https://github.com/kivy/kivy-ios) and currently uses Python 3.10.10.

## What Python packages are supported?

All "pure" Python packages, i.e. packages that implemented in Python only, without native extensions written in C, Rust or other language.

Packages with native extensions having a [recipe](https://github.com/kivy/kivy-ios/tree/master/kivy_ios/recipes) to build them for iOS.

## Building custom Python distributive

TBD