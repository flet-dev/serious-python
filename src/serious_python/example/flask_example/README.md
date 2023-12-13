# flask_example

Before running the app run the following command to package Python app to an asset:

when packaging for a desktop app:

```
dart run serious_python:main package app/src
```

when packaging for a mobile app:

```
dart run serious_python:main package app/src --mobile
```

Important: to make `serious_python` work in your own Android app:

If you build an App Bundle Edit `android/gradle.properties` and add the flag:

```
android.bundle.enableUncompressedNativeLibs=false
```


If you build an APK Make sure `android/app/src/AndroidManifest.xml` has `android:extractNativeLibs="true"` in the `<application>` tag.

For more information, see the [public issue](https://issuetracker.google.com/issues/147096055).