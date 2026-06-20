# flask_example

Before running the app run the following command to package Python app to an asset.

For Android:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src -p Android -r -r -r app/src/requirements.txt
```

For iOS:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src -p iOS -r -r -r app/src/requirements.txt
```

For macOS:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src -p Darwin -r -r -r app/src/requirements.txt
```

For Windows:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src -p Windows -r -r -r app/src/requirements.txt
```

For Linux:

```
export SERIOUS_PYTHON_SITE_PACKAGES=$(pwd)/build/site-packages
export SERIOUS_PYTHON_APP=$(pwd)/build/python-app
dart run serious_python:main package app/src -p Linux -r -r -r app/src/requirements.txt
```

For Android, no special native-library packaging config is required.
`serious_python` relocates Python extension modules into `jniLibs` and loads them
directly from the APK (memory-mapped, no extraction), and ships pure Python in
stored asset zips. Just use a `minSdk` of 23+ so native libs stay uncompressed and
page-aligned in the APK:

```kotlin
android {
    defaultConfig {
        minSdk = 23
    }
}
```