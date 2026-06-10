python_version=${1:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_ios

# Pinned dart-bridge release (flet-dev/dart-bridge). The xcframework is abi3 and
# version-independent of CPython, so one binary covers all 3.12+ Python versions.
dart_bridge_version=${DART_BRIDGE_VERSION:-1.2.1}

if [ ! -d "$dist" ]; then
    mkdir -p $dist

    python_ios_dist_file="python-ios-dart-$python_version.tar.gz"
    python_ios_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_ios_dist_file"

    # download iOS dist
    curl -LO $python_ios_dist_url
    tar -xzf $python_ios_dist_file -C $dist
    mv $dist/python-stdlib $dist/stdlib
    rm $python_ios_dist_file
fi

# dart_bridge.xcframework — separate cache guard so a stale dist_ios from before
# this change still picks up the new artifact on first re-prepare.
if [ ! -d "$dist/xcframeworks/dart_bridge.xcframework" ]; then
    mkdir -p "$dist/xcframeworks"
    dart_bridge_file="dart_bridge-apple.xcframework.zip"
    dart_bridge_url="https://github.com/flet-dev/dart-bridge/releases/download/v$dart_bridge_version/$dart_bridge_file"
    curl -fL -o "$dart_bridge_file" "$dart_bridge_url"
    unzip -q "$dart_bridge_file" -d "$dist/xcframeworks/"
    rm "$dart_bridge_file"
fi