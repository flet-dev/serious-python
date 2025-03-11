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
dart run serious_python:main package app/src -p Pyodide -r -r -r app/src/requirements.txt
```

For Android:

In `android/app/build.gradle`:

```
android {
    ndkVersion "25.1.8937393"

    packagingOptions {
        jniLibs {
            useLegacyPackaging true
        }
    }

    packagingOptions {
        doNotStrip "*/arm64-v8a/libpython*.so"
        doNotStrip "*/armeabi-v7a/libpython*.so"
        doNotStrip "*/x86/libpython*.so"
        doNotStrip "*/x86_64/libpython*.so"
    }
}
```