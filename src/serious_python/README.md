# serious_python

A cross-platform plugin for adding embedded Python runtime to your Flutter apps.

Serious Python embeds Python runtime into a mobile or desktop Flutter app to run a Python program on a background, without blocking UI. Processing files, working with SQLite databases, calling REST APIs, image processing, ML, AI and other heavy lifting tasks can be conveniently done in Python and run directly on a mobile device.

Build app backend service in Python and host it inside a Flutter app. Flutter app is not directly calling Python functions or modules, but instead communicating with Python environmnent via some API provided by a Python program, such as: REST API, sockets, SQLite database or files.

Serious Python is part of [Flet](https://flet.dev) project - the fastest way to build Flutter apps in Python. The motivation for building Serious Python was having a re-usable easy-to-use plugin, maintained and supported, to run real-world Python apps, not just "1+2" or "hello world" examples, on iOS or Android devices and hence the name "Serious Python".

## Platform Support

| iOS     |   Android    |   macOS    |   Linux    |   Windows    |
| :-----: | :----------: | :---------: | :-------: | :----------: |
|   ✅    |       ✅      |       ✅    |     ✅     |      ✅      |

### Python versions

* iOS: Python 3.11.6 - based on [Kivy toolchain](https://github.com/kivy/kivy-ios).
* Android: Python 3.11.6 - based on [Kivy python-for-android](https://github.com/kivy/python-for-android).
* macOS: Python 3.11.6 - based on [Beeware's Python Apple Support](https://github.com/beeware/Python-Apple-support).
* Linux: Python 3.11.6 - based on [indygreg/python-build-standalone](https://github.com/indygreg/python-build-standalone).
* Windows: Python 3.11.6 - based on [CPython](https://www.python.org/downloads/release/python-3116/).

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

There is `package` command which takes a directory with Python app as the first argument. The command must be run in Flutter app root directory, where `pubspec.yaml` is located. The path could be either relative or an absolute.

To package Python files for a mobile app run: 

```
dart run serious_python:main package app/src --mobile
```

To package for a desktop app run:

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

## Adding custom Python libraries

### iOS

`serious_python` uses [Kivy for iOS](https://github.com/kivy/kivy-ios) to build Python and native Python packages for iOS.

Python static library and its dependencies are downloaded and installed during project pod installation from [`serious_python` releases](https://github.com/flet-dev/serious-python/releases).

To build your own Python distributive with custom native packages and use it with `serious_python` you need to use `toolchain` tool provided by Kivy for iOS.

`toolchain` command-line tool can be run on macOS only.

Start with creating a new Python virtual environment and installing `kivy-ios` package as described [here](https://github.com/kivy/kivy-ios#installation--requirements).

Run `toolchain` command with the list of packages you need to build, for example to build `numpy`:

```
toolchain build numpy
```

**NOTE:** The library you want to build with `toolchain` command should have a recipe in [this folder](https://github.com/kivy/kivy-ios/tree/master/kivy_ios/recipes). You can [submit a request](https://github.com/kivy/kivy-ios/issues) to make a recipe for the library you need.

You can also install package that don't require compilation with `pip`:

```
toolchain pip install flask
```

This case you don't need to include that package into `requirements.txt` of your Python app.

When `toolchain` command is finished you should have everything you need in `dist` directory.

Get the full path to `dist` directory by running `realpath dist` command.

In the terminal where you run `flutter` commands to build your Flet iOS app run the following command to
store `dist` full path in `SERIOUS_PYTHON_IOS_DIST` environment variable:

```bash
export SERIOUS_PYTHON_IOS_DIST="<full-path-to-dist-directory>"
```

Clean up old `build` directory by running:

```
flutter clean
```

Build your app by running `flutter ios` command.

You app's bundle now includes custom Python libraries.

### Android

`serious_python` uses [Kivy for Android](https://github.com/kivy/python-for-android) to build Python and native Python packages for Android.

Python static library and its dependencies are downloaded and installed on pre-build step of Gradle project from [`serious_python` releases](https://github.com/flet-dev/serious-python/releases).

To build your own Python distributive with custom native packages and use it with `serious_python` you need to use `p4a` tool provided by Kivy for Android.

`p4a` command-line tool can be run on macOS and Linux.

To get Android SDK install Android Studio.

On macOS Android SDK will be located at `$HOME/Library/Android/sdk`.

Install Temurin8 to get JRE 1.8 required by `sdkmanager` tool:

```bash
brew install --cask temurin8
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home
```

Set the following environment variables:

```bash
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export NDK_VERSION=25.2.9519653
export SDK_VERSION=android-33
```

Add path to `sdkmanager` to `PATH`:

```bash
export PATH=$ANDROID_SDK_ROOT/tools/bin:$PATH
```

Install Android SDK and NDK from https://developer.android.com/ndk/downloads/ or with Android SDK Manager:

```bash
echo "y" | sdkmanager --install "ndk;$NDK_VERSION" --channel=3
echo "y" | sdkmanager --install "platforms;$SDK_VERSION"
```

Create new Python virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Install `p4a`:

```
pip install python-for-android
```

Install `cython`:

```
pip install --upgrade cython
```

Run `p4a` with `--requirements` including your custom Python libraries separated with comma, like `numpy` in the following example:

```
p4a create --requirements numpy --arch arm64-v8a --arch armeabi-v7a --arch x86_64 --sdk-dir $ANDROID_SDK_ROOT --ndk-dir $ANDROID_SDK_ROOT/ndk/$NDK_VERSION --dist-name serious_python
```

*Choose No to "Do you want automatically install prerequisite JDK? [y/N]".*

**NOTE:** The library you want to build with `p4a` command should have a recipe in [this folder](https://github.com/kivy/python-for-android/tree/develop/pythonforandroid/recipes). You can [submit a request](https://github.com/kivy/python-for-android/issues) to make a recipe for the library you need.

When `p4a` command completes a Python distributive with your custom libraries will be located at:

```
$HOME/.python-for-android/dists/serious_python
```

In the terminal where you run `flutter` commands to build your Flet Android app run the following command to store distributive full path in `SERIOUS_PYTHON_P4A_DIST` environment variable:

```bash
export SERIOUS_PYTHON_P4A_DIST=$HOME/.python-for-android/dists/serious_python
```

Clean up old `build` directory by running:

```
flutter clean
```

Build your app by running `flutter appbundle` command to build `.apk`.

You app's bundle now includes custom Python libraries.

### macOS

List libraries and their versions in `requirements.txt` in the root of your Python app directory.

### Windows

List libraries and their versions in `requirements.txt` in the root of your Python app directory.

### Linux

List libraries and their versions in `requirements.txt` in the root of your Python app directory.

## Troubleshooting

### Detailed logging

Use `--verbose` flag to enabled detailed logging:

```
dart run serious_python:main package app/src --mobile --verbose
```

## Examples

[Python REPL with Flask backend](src/serious_python/example/flask_example).

[Flet app](src/serious_python/example/flet_example).

[Run Python app](src/serious_python/example/run_example).
