# flet_example

Before running the app run the following command to package Python app to an asset.

For Android:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p Android --requirements -r,app/src/requirements.txt
```

For iOS:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
dart run serious_python:main package app/src -p iOS --requirements -r,app/src/requirements.txt
```

For macOS:

```
dart run serious_python:main package app/src -p Darwin --requirements -r,app/src/requirements.txt
```

For Windows:

```
dart run serious_python:main package app/src -p Windows --requirements -r,app/src/requirements.txt
```

For Linux:

```
dart run serious_python:main package app/src -p Linux --requirements -r,app/src/requirements.txt
```

For web:

```
dart run serious_python:main package app/src -p Pyodide --requirements -r,app/src/requirements.txt
```

Important: to make `serious_python` work in your own Android app:

If you build an App Bundle Edit `android/gradle.properties` and add the flag:

```
android.bundle.enableUncompressedNativeLibs=false
```


If you build an APK Make sure `android/app/src/AndroidManifest.xml` has `android:extractNativeLibs="true"` in the `<application>` tag.

For more information, see the [public issue](https://issuetracker.google.com/issues/147096055).

Add the following to `android/app/build.gradle`:

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