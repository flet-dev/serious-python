# run_example

Before running the app run the following command to package Python app to an asset.

For Android:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p Android -r -r -r app/src/requirements.txt
```

For iOS:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p iOS -r -r -r app/src/requirements.txt
```

For macOS:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p Darwin -r -r -r app/src/requirements.txt
```

For Windows:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p Windows -r -r -r app/src/requirements.txt
```

For Linux:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p Linux -r -r -r app/src/requirements.txt
```

For Pyodide:

```
dart run serious_python:main package app/src -p Emscripten -r -r -r app/src/requirements.txt
```

For Android:

In `android/app/build.gradle.kts`:

```kotlin
android {
    // serious_python bundles libpython*.so. Use legacy (extracted, uncompressed)
    // packaging so the embedded interpreter can dlopen them at runtime, and keep
    // their symbols so they are not stripped.
    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols += setOf(
                "*/arm64-v8a/libpython*.so",
                "*/armeabi-v7a/libpython*.so",
                "*/x86/libpython*.so",
                "*/x86_64/libpython*.so",
            )
        }
    }

    defaultConfig {
        minSdk = 23
    }
}
```