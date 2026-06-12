# flet_example

A Flet counter app running on `serious_python`'s in-process
`dart_bridge` FFI transport. The Dart side constructs a `PythonBridge`
and hands a custom `FletBackendChannel` to `FletApp` via the
`channelBuilder` parameter; the Python side picks up
`FLET_DART_BRIDGE_PORT` from the environment and `flet.app.run_async()`
selects `FletDartBridgeServer` instead of the legacy
`FletSocketServer`.

The `flet` Dart package itself stays Python-independent — the
PythonBridge wiring lives entirely in this example.

## Building

The Python `flet` package needs the `dart-bridge` branch (because
`FletDartBridgeServer` isn't on PyPI yet), so the `--requirements` arg
installs from git. Mobile targets use `pip install --only-binary :all:`
which would normally reject a git source — the
`SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS=flet` env var opts `flet`
specifically into source installs by injecting `--no-binary flet`.

For macOS:

```
export SERIOUS_PYTHON_ALLOW_SOURCE_DISTRIBUTIONS=flet
dart run serious_python:main package app/src \
  --platform Darwin \
  --requirements "flet @ git+https://github.com/flet-dev/flet.git@dart-bridge#subdirectory=sdk/python/packages/flet"
```

Replace `--platform Darwin` with `iOS`, `Android`, `Windows`, or `Linux`
as needed. The same `--requirements` works on every platform.

## Running locally

`sync_site_packages.sh` (in `serious_python_darwin`) requires
`SERIOUS_PYTHON_SITE_PACKAGES` pointing at the freshly-packaged
`build/site-packages/` directory so the .app bundle picks up the
git-installed flet instead of a stale copy from a previous run:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
fvm flutter test integration_test --device-id macos
```
