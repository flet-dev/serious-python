script_dir=$(cd "$(dirname "$0")" && pwd -P)

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
        rsync -av --delete "$SERIOUS_PYTHON_SITE_PACKAGES/" "$dist/site-packages/"
    fi
else
    echo "SERIOUS_PYTHON_SITE_PACKAGES is not set."
fi