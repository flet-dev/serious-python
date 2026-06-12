python_version=${1:?}
python_full_version=${2:?}
python_build_date=${3:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_ios

# Pinned dart-bridge release (flet-dev/dart-bridge). The xcframework is abi3 and
# version-independent of CPython, so one binary covers all 3.12+ Python versions.
dart_bridge_version=${DART_BRIDGE_VERSION:-1.2.1}

# Cross-plugin download cache; see prepare_macos.sh for the convention.
cache_root="${FLET_CACHE_DIR:-$HOME/.flet/cache}"
pb_cache="$cache_root/python-build/v$python_full_version"
db_cache="$cache_root/dart-bridge/v$dart_bridge_version"
mkdir -p "$pb_cache" "$db_cache"

# ---- flet-dev/python-build (iOS embedded Python runtime) ------------------
python_ios_dist_file="python-ios-dart-$python_full_version.tar.gz"
python_ios_dist_path="$pb_cache/$python_ios_dist_file"
if [ ! -f "$python_ios_dist_path" ]; then
    python_ios_dist_url="https://github.com/flet-dev/python-build/releases/download/$python_build_date/$python_ios_dist_file"
    curl -fL -o "$python_ios_dist_path.tmp" "$python_ios_dist_url"
    mv "$python_ios_dist_path.tmp" "$python_ios_dist_path"
fi

if [ ! -d "$dist" ]; then
    mkdir -p "$dist"
    tar -xzf "$python_ios_dist_path" -C "$dist"
    mv "$dist/python-stdlib" "$dist/stdlib"
fi

# ---- flet-dev/dart-bridge (xcframework) -----------------------------------
# Separate cache guard so a stale $dist from before this change still picks
# up the new artifact on first re-prepare.
dart_bridge_file="dart_bridge-apple.xcframework.zip"
dart_bridge_path="$db_cache/$dart_bridge_file"
if [ ! -f "$dart_bridge_path" ]; then
    dart_bridge_url="https://github.com/flet-dev/dart-bridge/releases/download/v$dart_bridge_version/$dart_bridge_file"
    curl -fL -o "$dart_bridge_path.tmp" "$dart_bridge_url"
    mv "$dart_bridge_path.tmp" "$dart_bridge_path"
fi

if [ ! -d "$dist/xcframeworks/dart_bridge.xcframework" ]; then
    mkdir -p "$dist/xcframeworks"
    unzip -q "$dart_bridge_path" -d "$dist/xcframeworks/"
fi
