# flet_example

## install flutter and all it's dependencies

## add your py files in app dir

## compile and zip your py files using

```bash
dart run serious_python:main package --asset app/app.zip  python/
```

or using
> make compile

## build your apk

```bash
flutter build apk --split-per-abi 
```

or using
> make bundle

you will find your apks in build/app/outpus/apk/release dir

or maybe just test it in your mobile or even in emulator using flutter run or debug as you like
