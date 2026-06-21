script_dir=$(cd "$(dirname "$0")" && pwd -P)

# App sources are arch- and platform-independent; stage them as a bare `app/`
# resource bundle into BOTH dist trees, regardless of whether site-packages
# exist (an app may have no pip dependencies). The per-target resource bundle
# (dist_ios / dist_macos) picks the right one at build time. This MUST run
# outside the SERIOUS_PYTHON_SITE_PACKAGES guard below — otherwise a
# dependency-free app never gets bundled and the runtime can't find main.py.
if [[ -n "$SERIOUS_PYTHON_APP" && -d "$SERIOUS_PYTHON_APP" ]]; then
    for app_dist in "$script_dir/dist_ios" "$script_dir/dist_macos"; do
        rm -rf "$app_dist/app"
        mkdir -p "$app_dist/app"
        rsync -a --exclude '.pod' "$SERIOUS_PYTHON_APP/" "$app_dist/app/"
    done
fi

if [[ -n "$SERIOUS_PYTHON_SITE_PACKAGES" && -d "$SERIOUS_PYTHON_SITE_PACKAGES" ]]; then

    if [[ -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphoneos.arm64" && -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphonesimulator.arm64" && -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphonesimulator.x86_64" ]]; then

        echo "Sync iOS xcframeworks and site-packages"
        dist=$script_dir/dist_ios

        # app xcframeworks
        rm -rf $dist/site-xcframeworks
        mkdir -p $dist/site-xcframeworks
        cp -R $dist/python-xcframeworks/* $dist/site-xcframeworks

        source $script_dir/xcframework_utils.sh

        tmp_dir=$(mktemp -d)

        cp -R $SERIOUS_PYTHON_SITE_PACKAGES/* $tmp_dir

        echo "Converting dylibs to xcframeworks..."
        find "$tmp_dir/${archs[0]}" -name "*.$dylib_ext" | while read full_dylib; do
            dylib_relative_path=${full_dylib#$tmp_dir/${archs[0]}/}
            create_xcframework_from_dylibs \
                "$tmp_dir/${archs[0]}" \
                "$tmp_dir/${archs[1]}" \
                "$tmp_dir/${archs[2]}" \
                $dylib_relative_path \
                "Frameworks/serious_python_darwin.framework/python.bundle/site-packages" \
                $dist/site-xcframeworks
        done

        rm -rf $dist/site-packages
        mkdir -p $dist/site-packages
        cp -R $tmp_dir/${archs[0]}/* $dist/site-packages

        # cleanup
        rm -rf "${tmp_dir}" >/dev/null

    else

        echo "Sync macOS xcframeworks and site-packages"
        dist=$script_dir/dist_macos

        mkdir -p $dist/site-packages
        # Exclude the .pod symlink created by symlink_pod.sh — it points at
        # this plugin's source tree. If it lands in dist_macos/site-packages,
        # CocoaPods packages it into the production .app, where macOS
        # LaunchServices finds the embedded Python.app inside the symlinked
        # Python.xcframework and tries to launch it (DYLD failure, repeated
        # crash report popups), and `flet build`'s copy_tree follows the
        # symlink into a code-signed source tree and hits EPERM on every
        # file. .pod is only needed by package_command.dart at packaging
        # time to invoke this sync script; it does not belong in the bundle.
        rsync -av --delete --exclude '.pod' "$SERIOUS_PYTHON_SITE_PACKAGES/" "$dist/site-packages/"
    fi
fi
