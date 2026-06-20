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

`SERIOUS_PYTHON_VERSION` (short, e.g. `3.14`) is the only input you set — the
full version, python-build release date, Pyodide version/tag, and dart_bridge
version all derive from it. (`SERIOUS_PYTHON_FULL_VERSION`,
`SERIOUS_PYTHON_BUILD_DATE`, `DART_BRIDGE_VERSION` exist as rarely-needed escape
hatches.) A single `export SERIOUS_PYTHON_VERSION=3.13` covers both the
packaging phase and the later Flutter build.

Source of truth: the date-keyed `manifest.json` published by
[`flet-dev/python-build`](https://github.com/flet-dev/python-build).
serious_python pins one release and commits generated snapshots of it —
`lib/src/python_versions.dart` (used by the CLI) and a `python_versions.properties`
in each platform package (read by the native build configs). To bump versions
see [CONTRIBUTING.md](CONTRIBUTING.md); never hand-edit the generated files.
Pre-release CPython lines are marked `prerelease: true`, so they're opt-in via
explicit `--python-version` (or `requires-python = "==3.15.*"`) without becoming
the auto-resolved default.

## Usage

Import Serious Python package into your app:

`import 'package:serious_python/serious_python.dart';`

The plugin is built against iOS 13.0, so you might need to update iOS version in `ios/Podfile`:

```bash
# Uncomment this line to define a global platform for your project
platform :ios, '13.0'
```

Package your Python app with the CLI (see [Packaging Python app](#packaging-python-app) below). Its sources are placed **unpacked inside the app bundle**, next to the Python stdlib and site-packages — on Android they ship as a *stored* `app.zip` asset inside the APK and are unpacked once on first launch. Then run it:

```dart
SeriousPython.run();
```

`run()` resolves the packaged app, changes the current directory to a writable per-app data directory (`<application-support>/data`), and runs `main.py` (or `main.pyc`) in the root of the app.

> **Note:** the app directory is **read-only** inside the bundle (signed `.app`, iOS bundle, Program Files). Write your data — files, SQLite databases, etc. — under the current directory or another writable location, not next to your code.

If your Python app has a different entry point it could be specified with `appFileName` parameter:

```dart
SeriousPython.run(appFileName: "my_app.py");
```

You can pass a map with environment variables that should be available in your Python program:

```dart
SeriousPython.run(
    appFileName: "my_app.py",
    environmentVariables: {"a": "1", "b": "2"});
```

By default, Serious Python expects Python dependencies installed into `__pypackages__` directory in the root of app directory. You can add additional paths to look for 3rd-party packages using `modulePaths` parameter:

```dart
SeriousPython.run(
    appFileName: "my_app.py",
    modulePaths: ["/absolute/path/to/my/site-packages"]);
```

By default the Python program runs in a background thread so the Flutter UI stays responsive. Pass `sync: true` to run it on the calling thread instead — useful for short utility programs or when calling from a Dart isolate; long-running synchronous programs will freeze the UI on the main isolate:

```dart
SeriousPython.run(sync: true);
```

If you just need the path to the unpacked app (e.g. to drive the runtime yourself), call `SeriousPython.prepareApp()` — it returns the app directory, performing the one-time Android unpack if needed.

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

For **native** targets (`Android`, `iOS`, `Darwin`, `Windows`, `Linux`) the processed app is staged into the directory given by the `SERIOUS_PYTHON_APP` environment variable, and the platform's native build copies it into the app bundle (Android ships it as a *stored* `app.zip` asset, unpacked on first launch). For the **web** (`Emscripten`) target the command instead creates an `app/app.zip` asset (loaded by Pyodide in the browser); change its path/name with `--asset`:

```
dart run serious_python:main package --asset assets/myapp.zip app/src -p Emscripten
```

#### Selecting a Python version

Pick which CPython line to bundle with the **`SERIOUS_PYTHON_VERSION`
environment variable** (supported short versions today are **3.12**, **3.13**,
**3.14**; the default is the latest stable):

```
export SERIOUS_PYTHON_VERSION=3.13
dart run serious_python:main package app/src -p Android -r flet
```

`SERIOUS_PYTHON_VERSION` is read **in two places**: by the `package` command
above, and by each platform plugin's native build (`build.gradle`, the
`serious_python_darwin` podspec, the Linux/Windows `CMakeLists.txt`) when
`flutter build` runs later. A single `export` covers both phases.

> **Important:** the `package` command also accepts a `--python-version` flag,
> but it **only affects the `package` step** (which interpreter the
> site-packages are installed for) — it does **not** reach the later
> `flutter build`. Using the flag alone produces a **mismatched** app (e.g.
> 3.13 packages bundled with the default-latest `Python.framework` / runtime).
> For a manual two-step build, set the `SERIOUS_PYTHON_VERSION` env var so both
> phases agree. (`flet build` exports it for you.)

See the [Python versions](#python-versions) table above for the matching CPython
and Pyodide releases.

> **Note:** changing the bundled Python version for an app you've already built
> requires a clean build (delete the app's `build/` directory, or run
> `flutter clean`) so stale compiled bytecode from the previous version isn't
> reused.

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

For all **native** platforms (`iOS`, `Android`, `Darwin`, `Windows`, `Linux`) set the `SERIOUS_PYTHON_SITE_PACKAGES` environment variable to a directory for the installed `pip` packages, and `SERIOUS_PYTHON_APP` to a directory for the processed app sources. The platform's native build embeds both into the app bundle during compilation (your app sources unpacked next to `site-packages`).

For example:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/app
dart run serious_python:main package app/src -p iOS -r -r -r app/src/requirements.txt
```

For the **web** (`Emscripten`) target there is no `SERIOUS_PYTHON_APP`; the app and its `__pypackages__` are zipped into the `app/app.zip` asset instead — make sure it's added to `pubspec.yaml`.

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

## How packaging works

`dart run serious_python:main package` assembles two things, which the platform plugin then bundles into your Flutter app:

1. **The CPython runtime + standard library** — a per-target build downloaded from [flet-dev/python-build](https://github.com/flet-dev/python-build) (and, for native extensions, [mobile-forge](https://github.com/flet-dev/mobile-forge)) and bundled by the plugin at build time.
2. **Your app + its dependencies** — your Python sources are placed **unpacked inside the app bundle**, next to the stdlib/site-packages (on Android they ship as a *stored* `app.zip` asset, and on the web inside `app/app.zip` — see below), and `pip`-installed packages are placed where each platform expects them.

At runtime the plugin sets `PYTHONHOME` / `PYTHONPATH` (or, on Android, installs a custom importer) so the interpreter finds the stdlib, your dependencies, and your app.

The on-disk layout differs per platform, mostly because each OS has different rules for shipping **native (compiled) extension modules** — the `.so`/`.pyd`/`.dylib` files inside packages like `numpy`:

| Platform | Standard library | Site-packages (deps) | Native extension modules | Architectures |
| --- | --- | --- | --- | --- |
| **Android** | `stdlib.zip` asset, read via `zipimport` | `sitepackages.zip` asset, read via `zipimport` | relocated to `jniLibs/<abi>/`, **memory-mapped from the APK** (no extraction), resolved by a custom importer | natives per-ABI in `jniLibs`; pure zips are ABI-common (shipped once) |
| **iOS** | dir inside the framework resource bundle | dir inside the framework resource bundle | each `.so` wrapped in a signed `.framework` inside an `.xcframework`, loaded via CPython's `AppleFrameworkLoader` (`.fwork` markers) | device `arm64` + simulator `arm64`/`x86_64` xcframework slices |
| **macOS** | dir inside the framework resource bundle | dir (universal) | universal (`lipo`'d `arm64`+`x86_64`) `.so`, loaded directly | `arm64`+`x86_64` merged into fat binaries |
| **Linux** | `<exe-dir>/python<X.Y>/` | `<exe-dir>/site-packages/` | on-disk `.so` (in `lib-dynload` / package dirs) | one of `x86_64` / `aarch64` per build |
| **Windows** | `<exe-dir>/Lib/` | `<exe-dir>/site-packages/` | on-disk `.pyd`/`.dll` in `<exe-dir>/DLLs/` | `x86_64` |
| **Web** | bundled inside Pyodide | `__pypackages__/` inside `app.zip` | Pyodide WebAssembly wheels | `wasm32` |

### Your app program (all platforms)

`package` copies your Python sources into a temp dir (honoring `--exclude` globs, optionally compiling to `.pyc` with `--compile-app`). For **native** platforms it stages them to `SERIOUS_PYTHON_APP`, and the platform build drops them **unpacked into the bundle** next to the stdlib/site-packages — `<resourcePath>/app` (iOS/macOS), `<exe-dir>/app` (Windows/Linux). There's no first-launch extraction; `SeriousPython.prepareApp()` just returns that path. On **Android** the sources are zipped into a *stored* `app.zip` asset and unpacked once (version-keyed by your app version) to `<application-support>/flet/app` on the first launch after an install/update. On the **web** they're zipped into `app/app.zip` and loaded by Pyodide. Your app dir is placed first on `sys.path`; a sibling `__pypackages__/` is also added (so you can vendor pure-Python deps next to your code). At run time the current directory is set to a writable `<application-support>/data` (the app dir itself is read-only).

`pip install` output goes to `build/site-packages` by default (override with the `SERIOUS_PYTHON_SITE_PACKAGES` env var). For mobile, packages are installed **per architecture** (a `sitecustomize.py` shim spoofs the wheel platform tag so the correct mobile wheels resolve), then merged or split per platform as shown above.

### Android specifics

- **Pure Python** (stdlib + dependencies) ships in two **stored** (uncompressed) ABI-common zips — `stdlib.zip` and `sitepackages.zip` — copied once (version-keyed) to `<application-support>/flet/` (alongside the unpacked `app/` and `extract/`) and imported in place via `zipimport`. Final `sys.path` (highest first): your app dir (`<application-support>/flet/app`), the extract dir, `sitepackages.zip`, `stdlib.zip`.
- **Native modules** (stdlib `lib-dynload` and site-package extensions) are relocated to `jniLibs/<abi>/lib<mangled>.so` and loaded **directly from the APK** (memory-mapped, never extracted to disk); a `sys.meta_path` finder resolves them from `.soref` markers left in the zips. This is why Android needs **no** `useLegacyPackaging` / `keepDebugSymbols` config and the stdlib is **not** duplicated per ABI.
- **Path-hungry packages** (those that read bundled data via `__file__` / `pkg_resources` rather than `importlib.resources`) can be shipped extracted to disk instead of inside the zip — list them (comma-separated relative paths) in `SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES`; they go into `extract.zip` and are unpacked to disk at first launch.
- Works for both **single APK** (`flutter build apk`) and **Play Store App Bundles** (per-ABI config splits); under legacy packaging / `minSdk < 23` the same finder falls back to loading from the extracted `nativeLibraryDir`.

### iOS / macOS specifics

The CPython runtime, stdlib, and (on iOS) native extensions are bundled into `serious_python_darwin.framework` as resources. On **iOS**, the App Store forbids loose `.dylib`s, so every native extension `.so` is repackaged into a signed `.framework` inside an `.xcframework`, with a `.fwork` text marker left at the module's import path; CPython's `AppleFrameworkLoader` reads the marker and loads the framework binary. On **macOS**, native extensions stay as plain `.so`, merged into universal (`arm64`+`x86_64`) binaries at package time. `PYTHONHOME` is the framework's resource path; `sys.path` includes `<resources>/site-packages`, `<resources>/stdlib`, and `<resources>/stdlib/lib-dynload`.

### Linux / Windows specifics

The CPython runtime (`libpython3.so` + `libpython<X.Y>.so` on Linux; `python3.dll` + `python<XY>.dll` on Windows), `libdart_bridge`, the stdlib, and native modules are copied next to your app's executable at build time. `PYTHONHOME` is the executable's directory. On Windows, extension modules (`.pyd`) and their dependent DLLs live in `<exe-dir>/DLLs/`, which is added to `sys.path`.

## Platform notes

### Build matrix

The following matrix shows which platform you should build on to target specific platforms:

| Build on / Target  |   iOS   |   Android   |   macOS    |   Linux    |   Windows    |    Web    |
| :----------------: | :-----: | :---------: | :--------: | :--------: | :----------: | :--------: |
| macOS              |   ✅    |       ✅     |      ✅    |           |              |     ✅     |
| Windows            |         |       ✅     |            |  ✅ (WSL)  |      ✅      |     ✅     |
| Linux              |         |       ✅     |            |     ✅     |              |     ✅     |


### macOS

macOS 11.0 (Big Sur) is the minimal supported version of macOS (the bundled
`Python.framework` requires 11.0).

You have to update your Flutter app's `macos/Podfile` to have this line at the very top:

```ruby
platform :osx, '11.0'
```

Also, make sure `macos/Runner.xcodeproj/project.pbxproj` contains:

```objc
MACOSX_DEPLOYMENT_TARGET = 11.0;
```

### Android

No special native-library packaging config is required (see [How packaging works](#how-packaging-works)). serious_python loads native modules directly from the APK and ships pure Python in stored asset zips, so you don't need `useLegacyPackaging`, `keepDebugSymbols`, `extractNativeLibs`, or `android.bundle.enableUncompressedNativeLibs`. Just use a `minSdk` of 23+ so native libs stay uncompressed/page-aligned in the APK:

```kotlin
android {
    defaultConfig {
        minSdk = 23
    }
}
```

## Troubleshooting

### Detailed logging

Use `--verbose` flag to enabled detailed logging:

```
dart run serious_python:main package app/src -p Darwin --verbose
```

## Examples

[Python REPL with Flask backend](example/flask_example).

[Run Python app](example/run_example).
