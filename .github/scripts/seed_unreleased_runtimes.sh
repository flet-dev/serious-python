#!/usr/bin/env bash
# Make runtimes that the pinned releases don't publish yet available to a build,
# by taking them from GitHub Actions runs of flet-dev/python-build and
# flet-dev/dart-bridge.
#
# serious_python downloads its Python runtime from the python-build release in
# `python_build_release_date` and its dart_bridge binary from dart-bridge
# release `v<dart_bridge_version>` (the generated python_versions.properties).
# A new Python minor is added to those tables before either release exists, so
# a build of that minor needs the files from CI artifacts instead:
#
#   * Darwin / iOS / Linux / Windows skip the download when the file is already
#     in serious_python's cache, so the artifact is placed there.
#   * Android re-checks the URL even when cached, so the archives are put in a
#     directory exported as SERIOUS_PYTHON_ANDROID_PYTHON_DIST (and the
#     dart_bridge .so files as SERIOUS_PYTHON_DART_BRIDGE_DIST).
#
# Files the releases already have are left alone, so this is a no-op for
# released minors and when both run ids are empty.
#
# Usage: seed_unreleased_runtimes.sh <Darwin|iOS|Android|Linux|Windows>
# Env:   SERIOUS_PYTHON_VERSION (short version), PYTHON_BUILD_RUN_ID, DART_BRIDGE_RUN_ID, GH_TOKEN,
#        FLET_CACHE_DIR (optional), GITHUB_ENV / RUNNER_TEMP (set by Actions).
set -euo pipefail

platform="${1:?platform}"
short="${SERIOUS_PYTHON_VERSION:?SERIOUS_PYTHON_VERSION is required}"
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
props="$root/src/serious_python_linux/linux/python_versions.properties"

prop() { sed -n "s/^$1=//p" "$props" | tr -d '\r'; }
full=$(prop "$short.full_version")
date=$(prop python_build_release_date)
dart_bridge=$(prop dart_bridge_version)
if [ -z "$full" ]; then
    echo "::error::$props has no $short.full_version"
    exit 1
fi

cache="${FLET_CACHE_DIR:-$HOME/.flet/cache}"
pb_cache="$cache/python-build/v$full-$date"
tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/sp-unreleased"
mkdir -p "$tmp"

release_assets() { # repo tag
    gh release view "$2" --repo "$1" --json assets --jq '.assets[].name' 2>/dev/null || true
}
pb_assets=$(release_assets flet-dev/python-build "$date")
db_assets=$(release_assets flet-dev/dart-bridge "v$dart_bridge")
has() { grep -qxF "$2" <<<"$1"; }

# download_artifact <repo> <run id> <artifact> -> prints the directory it is in.
download_artifact() {
    local dir="$tmp/$3"
    if [ ! -d "$dir" ]; then
        if [ -z "$2" ]; then
            echo "::error::$1 has not released $3's files and no run id is set to take them from" >&2
            return 1
        fi
        echo "Downloading artifact $3 from $1 run $2" >&2
        gh run download "$2" --repo "$1" --name "$3" --dir "$dir" >&2
    fi
    echo "$dir"
}

# seed_python <artifact> <file> <dest dir>
seed_python() {
    if has "$pb_assets" "$2"; then
        return 0
    fi
    local dir
    dir=$(download_artifact flet-dev/python-build "${PYTHON_BUILD_RUN_ID:-}" "$1")
    mkdir -p "$3"
    cp "$dir/$2" "$3/$2"
    echo "Seeded $3/$2 (python-build run ${PYTHON_BUILD_RUN_ID})"
}

export_env() {
    echo "$1=$2"
    if [ -n "${GITHUB_ENV:-}" ]; then
        echo "$1=$2" >> "$GITHUB_ENV"
    fi
}

case "$platform" in
    Darwin)
        seed_python "darwin-unsigned-$full" "python-macos-dart-$full.tar.gz" "$pb_cache"
        ;;
    iOS)
        seed_python "darwin-unsigned-$full" "python-ios-dart-$full.tar.gz" "$pb_cache"
        ;;
    Linux)
        case "$(uname -m)" in
            x86_64 | amd64) arch=x86_64 ;;
            aarch64 | arm64) arch=aarch64 ;;
            *) echo "::error::unsupported Linux arch $(uname -m)"; exit 1 ;;
        esac
        seed_python "python-linux-$full" "python-linux-dart-$full-$arch.tar.gz" "$pb_cache"
        ;;
    Windows)
        seed_python "python-windows-$full" "python-windows-for-dart-$full.zip" "$pb_cache"
        ;;
    Android)
        abis=$(prop "$short.android_abis" | tr ',' ' ')
        py_dist="$tmp/android-python-dist"
        bridge_dist="$tmp/android-dart-bridge-dist"
        need_py=0
        need_bridge=0
        for abi in $abis; do
            has "$pb_assets" "python-android-dart-$full-$abi.tar.gz" || need_py=1
            has "$db_assets" "libdart_bridge-android-$abi-py$short.so" || need_bridge=1
        done
        if [ "$need_py" = 1 ]; then
            # SERIOUS_PYTHON_ANDROID_PYTHON_DIST replaces the download for every
            # ABI, so the directory gets all of them.
            dir=$(download_artifact flet-dev/python-build "${PYTHON_BUILD_RUN_ID:-}" "python-android-$full")
            mkdir -p "$py_dist"
            for abi in $abis; do
                cp "$dir/python-android-dart-$full-$abi.tar.gz" "$py_dist/"
            done
            export_env SERIOUS_PYTHON_ANDROID_PYTHON_DIST "$py_dist"
        fi
        if [ "$need_bridge" = 1 ]; then
            mkdir -p "$bridge_dist"
            for abi in $abis; do
                name="libdart_bridge-android-$abi-py$short"
                dir=$(download_artifact flet-dev/dart-bridge "${DART_BRIDGE_RUN_ID:-}" "$name")
                cp "$dir/$name.so" "$bridge_dist/"
            done
            export_env SERIOUS_PYTHON_DART_BRIDGE_DIST "$bridge_dist"
        fi
        ;;
    *)
        echo "::error::unknown platform $platform"
        exit 1
        ;;
esac
