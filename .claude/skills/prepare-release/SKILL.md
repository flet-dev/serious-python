---
name: prepare-release
description: Use when asked to prepare a new serious_python release — optionally bump the bundled python-build snapshot, bump all package versions, regenerate version tables, and author CHANGELOG entries. Stops before tagging/publishing.
---

# Prepare a serious_python release

`serious_python` ships as six packages under `src/` that are versioned and released
together, all at the **same** version:

- `serious_python` (the CLI + Dart API; owns `bin/gen_version_tables.dart`)
- `serious_python_platform_interface`
- `serious_python_android`, `serious_python_darwin`, `serious_python_linux`, `serious_python_windows`

The bundled CPython runtimes come from `flet-dev/python-build`, whose date-keyed
(`YYYYMMDD`) `manifest.json` is the single source of truth for Python/Pyodide/
`dart_bridge`/ABI versions. The committed version tables are **generated** from it.

## Inputs to establish first

- **Target version.** Latest release is `git describe --tags --abbrev=0` (or the newest
  `## X.Y.Z` in `src/serious_python/CHANGELOG.md`). Patch bump → increment the third
  digit; minor/feature → second; major → first.
- **python-build snapshot.** Is this release also re-pinning python-build to a newer
  `YYYYMMDD` release? If yes, get the target date. If no, skip the "Bump python-build
  snapshot" section entirely.
- **What changed**, so the CHANGELOG is accurate: the merged PRs since the last release
  (`git log <lastTag>..HEAD`) and, if bumping the snapshot, what changed in python-build
  between the old and new release (see below).

## Tooling

Use the fvm-pinned Flutter/Dart, not a bare `dart` (see `.fvmrc`):

```
fvm dart --version          # should match .fvmrc
```

If `fvm` isn't on `PATH`, it's at `~/.fvm_flutter/bin/fvm`; the pinned SDK lives under
`~/fvm/versions/<version>`.

## Bump the python-build snapshot (only if re-pinning)

The version tables are generated — **do not hand-edit** `python_versions.dart` or the
`python_versions.properties` files.

1. Inspect what actually changed in the new python-build release, so you can write a
   truthful CHANGELOG (versions often don't move — a release may just rebuild one platform):
   ```
   gh release view <newDate> --repo flet-dev/python-build
   gh api repos/flet-dev/python-build/compare/<oldDate>...<newDate> \
     --jq '.commits[] | "- " + (.commit.message | split("\n")[0])'
   # and diff the manifests to see which version fields, if any, moved:
   # curl -sL .../download/<oldDate>/manifest.json  vs  <newDate>/manifest.json
   ```
2. Regenerate from the new manifest (run from the `serious_python` package dir):
   ```
   cd src/serious_python
   fvm dart pub get
   fvm dart run serious_python:gen_version_tables --release-date <newDate>
   ```
   This rewrites `lib/src/python_versions.dart` (incl. `pythonReleaseDate`) and the four
   `python_versions.properties` files under the native packages.
3. Verify the generator is idempotent (this is exactly the CI "Version tables in sync
   with manifest" check — the no-arg form reads the now-pinned date and must produce no
   further diff):
   ```
   fvm dart run serious_python:gen_version_tables   # no args
   git diff --stat -- '*python_versions*'            # no NEW changes beyond step 2
   ```

## Bump all package versions

Set the target version in every place (they must all match):

- `version:` in all six `src/*/pubspec.yaml`
- `version = "X.Y.Z"` in `src/serious_python_android/android/build.gradle.kts`
- `s.version = 'X.Y.Z'` in `src/serious_python_darwin/darwin/serious_python_darwin.podspec`

Inter-package dependencies are `path:`-based (no version constraints to bump). The example
apps' `pubspec.lock` files under `src/serious_python/example/*` pin path deps and can drift;
refresh with `fvm flutter pub get` in each if you want them current, but it's not required
for publishing.

Sanity check nothing stale remains:
```
grep -rn "<oldVersion>" src/ --include='*.yaml' --include='*.kts' --include='*.podspec' --include='*.dart'
```

## Author CHANGELOG entries

Add a `## X.Y.Z` section at the top of each package's `CHANGELOG.md`. Match the existing
tone/format. Route the content to the package it actually belongs to:

- Put the substantive, mechanism-level entry in the affected native package (e.g. an
  iOS/macOS fix → `serious_python_darwin`), and a user-facing one-line summary that
  cross-references it (`See serious_python_darwin X.Y.Z.`) in the top-level `serious_python`.
- Packages with no real change get an alignment line, e.g.
  `Version bump aligning with the serious_python_* X.Y.Z release.`
- If you bumped the snapshot but a platform's binaries are byte-identical to the previous
  snapshot, say so (`Bump the bundled python-build snapshot to <newDate>; <platform>
  runtimes are byte-identical to <oldDate>.`).
- Only include real, user-relevant items tied to a PR/issue — skip chore/trivial/duplicate
  commits.

## Finish

- Do **not** run on `main` directly — create a branch (e.g. `bump-X.Y.Z`), commit, and open
  a PR (this is how prior bumps landed, e.g. #221). Mirror the prior commit-message style
  ("Bump to X.Y.Z: <headline>") unless told otherwise.
- **Do not tag, release, or publish.** CI being green is not a signal to release. Tagging and
  publishing to pub.dev happen only on an explicit, in-session request from the user — never
  autonomously.
