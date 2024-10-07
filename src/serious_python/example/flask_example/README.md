# flask_example

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

Important: to make `serious_python` work in your own Android app:

If you build an App Bundle Edit `android/gradle.properties` and add the flag:

```
android.bundle.enableUncompressedNativeLibs=false
```

If you build an APK Make sure `android/app/src/AndroidManifest.xml` has `android:extractNativeLibs="true"` in the `<application>` tag.

For more information, see the [public issue](https://issuetracker.google.com/issues/147096055).