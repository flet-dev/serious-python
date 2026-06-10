python_version=${1:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_macos

# Pinned dart-bridge release (flet-dev/dart-bridge). Same xcframework is reused
# across iOS and macOS — it carries slices for both.
dart_bridge_version=${DART_BRIDGE_VERSION:-1.2.1}

if [ ! -d "$dist" ]; then
    mkdir -p $dist

    python_macos_dist_file="python-macos-dart-$python_version.tar.gz"
    python_macos_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_macos_dist_file"

    # download macos dist
    curl -LO $python_macos_dist_url
    tar -xzf $python_macos_dist_file -C $dist
    mv $dist/python-stdlib $dist/stdlib
    rm $python_macos_dist_file
fi

if [ ! -d "$dist/xcframeworks/dart_bridge.xcframework" ]; then
    mkdir -p "$dist/xcframeworks"
    dart_bridge_file="dart_bridge-apple.xcframework.zip"
    dart_bridge_url="https://github.com/flet-dev/dart-bridge/releases/download/v$dart_bridge_version/$dart_bridge_file"
    curl -fL -o "$dart_bridge_file" "$dart_bridge_url"
    unzip -q "$dart_bridge_file" -d "$dist/xcframeworks/"
    rm "$dart_bridge_file"
fi