# run_example

Before running the app run the following command to package Python app to an asset:

when packaging for iOS:

```
dart run serious_python:main package app/src -p iOS -r lru-dict,yarl,numpy
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