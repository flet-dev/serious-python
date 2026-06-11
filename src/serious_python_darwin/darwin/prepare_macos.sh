python_version=${1:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_macos

# Pinned dart-bridge release (flet-dev/dart-bridge). Same xcframework is reused
# across iOS and macOS — it carries slices for both.
dart_bridge_version=${DART_BRIDGE_VERSION:-1.2.1}

# Cross-plugin download cache. FLET_CACHE_DIR is the same env var the Android
# gradle task + flet build's external tooling already use; ~/.flet/cache is
# the shared default. Tarballs land here and survive `flutter clean`.
cache_root="${FLET_CACHE_DIR:-$HOME/.flet/cache}"
pb_cache="$cache_root/python-build/v$python_version"
db_cache="$cache_root/dart-bridge/v$dart_bridge_version"
mkdir -p "$pb_cache" "$db_cache"

# ---- flet-dev/python-build (macOS embedded Python runtime) ----------------
python_macos_dist_file="python-macos-dart-$python_version.tar.gz"
python_macos_dist_path="$pb_cache/$python_macos_dist_file"
if [ ! -f "$python_macos_dist_path" ]; then
    python_macos_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_macos_dist_file"
    # .tmp + mv so a Ctrl-C / network blip doesn't poison the cache.
    curl -fL -o "$python_macos_dist_path.tmp" "$python_macos_dist_url"
    mv "$python_macos_dist_path.tmp" "$python_macos_dist_path"
fi

if [ ! -d "$dist" ]; then
    mkdir -p "$dist"
    tar -xzf "$python_macos_dist_path" -C "$dist"
    mv "$dist/python-stdlib" "$dist/stdlib"
fi

# ---- flet-dev/dart-bridge (xcframework, same archive for macOS + iOS) -----
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
