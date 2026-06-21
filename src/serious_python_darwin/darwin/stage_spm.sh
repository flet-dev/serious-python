#!/usr/bin/env bash
set -euo pipefail
#
# stage_spm.sh <ios|macos>
#
# Host-side staging for the Swift Package Manager build path. Maps the assembled
# dist_<platform> tree (produced by prepare_<platform>.sh + sync_site_packages.sh)
# into the SPM plugin layout under serious_python_darwin/, which Package.swift
# consumes as local-path binaryTargets + .copy resources. Prints the cache-bust
# key (SP_NATIVE_SET) on stdout — the caller exports it into the `flutter build`
# environment so SwiftPM re-resolves when the staged native set changes.
#
platform=${1:?usage: stage_spm.sh <ios|macos>}
script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist="$script_dir/dist_$platform"
pkg="$script_dir/serious_python_darwin"
res="$pkg/Sources/serious_python_darwin/Resources"

[ -d "$dist" ] || { echo "stage_spm: $dist not found" >&2; exit 1; }

# 1. Python runtime (dynamic framework -> embedded). Platform-specific path so a
#    single shared manifest can carry both via platform-conditional binaryTargets.
rm -rf "$pkg/Python-$platform.xcframework"
cp -R "$dist/xcframeworks/Python.xcframework" "$pkg/Python-$platform.xcframework"

# 2. dart_bridge (static, version-independent; same artifact in either dist).
rm -rf "$pkg/dart_bridge.xcframework"
cp -R "$dist/xcframeworks/dart_bridge.xcframework" "$pkg/dart_bridge.xcframework"

# 3. iOS native C-extensions (stdlib lib-dynload + site-packages) -> enumerated
#    binaryTargets. macOS has none: its .so's load flat from the resource trees.
rm -rf "$pkg/extra-xcframeworks"
if [ "$platform" = "ios" ] && [ -d "$dist/site-xcframeworks" ]; then
    mkdir -p "$pkg/extra-xcframeworks"
    cp -R "$dist"/site-xcframeworks/*.xcframework "$pkg/extra-xcframeworks/" 2>/dev/null || true
fi

# 4. Resource trees (verbatim via rsync). Wipe prior content but keep the
#    committed .keep placeholder so the path stays valid in a clean checkout.
for tree in stdlib site-packages app; do
    dest="$res/$tree"
    mkdir -p "$dest"
    find "$dest" -mindepth 1 -not -name '.keep' -delete 2>/dev/null || true
    [ -d "$dist/$tree" ] && rsync -a --exclude '.pod' "$dist/$tree/" "$dest/"
done

# 5. Cache-bust key: platform + Python version + the staged native/resource set
#    (path+size). Changes whenever requirements, app, or Python version change.
key_paths=("Python-$platform.xcframework" "Sources/serious_python_darwin/Resources")
[ -d "$pkg/extra-xcframeworks" ] && key_paths+=("extra-xcframeworks")
key=$(
  {
    echo "$platform ${SERIOUS_PYTHON_FULL_VERSION:-}"
    ( cd "$pkg" && find "${key_paths[@]}" -type f -exec stat -f '%N %z' {} + \
        2>/dev/null | sort )
  } | shasum -a 256 | cut -d' ' -f1
)
echo "$key"
