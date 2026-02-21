---
name: prepare-release
description: Use when asked to prepare new serious_python release by bumping versions and author release notes.
---

## Inputs

* Previous serious_python version from repo tags.
* Whether it's minor or major release.

## Steps

* Take latest serious_python release version from the repo and
  increment third (patch) digit to get the next version if it's a minor release
  or second (minor) digit if it's a major release.
* Set new version in pubspec.yaml of all packages in /src.
* Set new s.version in src/serious_python_darwin/darwin/serious_python_darwin.podspec.
* Set new version in src/serious_python_android/android/build.gradle.
* Run pub get for all apps in src/serious_python/example to refresh their pubspec.lock with new version.
* Add a new entry into all packages' CHANGELOG.md from a git log since the last release. Do not add chore/trivial/duplicate items, add items with related issue or PR.
