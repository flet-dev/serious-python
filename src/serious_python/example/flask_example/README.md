# flask_example

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

Important: to make `serious_python` work in your own Android app, the bundled
`libpython*.so` must be shipped uncompressed and extracted so the embedded
interpreter can `dlopen` them at runtime. In `android/app/build.gradle.kts`:

```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
```

`useLegacyPackaging = true` is the modern replacement (AGP 8.1+) for both the
old `android.bundle.enableUncompressedNativeLibs=false` gradle property and the
`android:extractNativeLibs="true"` manifest attribute, and it covers both APK and
App Bundle builds. See the [public issue](https://issuetracker.google.com/issues/147096055).