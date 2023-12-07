# run_example

Before running the app run the following command to package Python app to an asset:

when packaging for a desktop app:

```
dart run serious_python:main package app/src --req-deps "flet"
```

when packaging for a mobile app:

```
dart run serious_python:main package app/src --mobile --dep-mappings "flet>flet-embed" --req-deps "flet-embed"
```