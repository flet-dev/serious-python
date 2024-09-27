# flet_example

Before running the app run the following command to package Python app to an asset.

For macOS:

```
dart run serious_python:main package app/src -p Darwin -r flet==0.25.0.dev3422,lru-dict
```

For Windows:

```
dart run serious_python:main package app/src -p Windows -r flet==0.25.0.dev3422,lru-dict
```

when packaging for a desktop app:

```
dart run serious_python:main package app/src --dep-mappings "flet=flet-embed" --req-deps "flet-embed"
```

when packaging for a mobile app:

```
dart run serious_python:main package app/src --mobile --dep-mappings "flet=flet-embed" --req-deps "flet-embed"
```

when packaging for a web app:

```
dart run serious_python:main package app/src --web --dep-mappings "flet=flet-pyodide" --req-deps "flet-pyodide" --platform emscripten_3_1_45_wasm32
```

Important: to make `serious_python` work in your own Android app:

If you build an App Bundle Edit `android/gradle.properties` and add the flag:

```
android.bundle.enableUncompressedNativeLibs=false
```


If you build an APK Make sure `android/app/src/AndroidManifest.xml` has `android:extractNativeLibs="true"` in the `<application>` tag.

For more information, see the [public issue](https://issuetracker.google.com/issues/147096055).