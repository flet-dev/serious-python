echo "Bundle Python xcframeworks"

python_version=${1:?}
dist=${2:?}

# app xcframeworks
rm -rf $dist/site-xcframeworks
mkdir -p $dist/site-xcframeworks
cp -R $dist/python-xcframeworks/* $dist/site-xcframeworks

# convert site-packages to xcframeworks
if [ -n "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then

    . $PODS_TARGET_SRCROOT/xcframework_utils.sh

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
            "Frameworks/serious_python_darwin.framework/site-packages" \
            $dist/site-xcframeworks
    done

    rm -rf $dist/site-packages
    mkdir -p $dist/site-packages
    cp -R $tmp_dir/${archs[0]}/* $dist/site-packages

    # cleanup
    rm -rf "${tmp_dir}" >/dev/null
fi

# modify Flutter packaging script to include user frameworks
pods_runner_frameworks_script="$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"

if ! grep -q "added by serious_python_darwin plugin" "$pods_runner_frameworks_script"; then
    echo "" >> $pods_runner_frameworks_script
    echo "PYTHON_XCFRAMEWORKS_ROOT=\x22$dist/site-xcframeworks\x22" >> $pods_runner_frameworks_script
    cat $PODS_TARGET_SRCROOT/pods-runner-frameworks-addon.sh >> $pods_runner_frameworks_script
fi