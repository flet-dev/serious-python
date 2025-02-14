echo "Sync iOS xcframeworks and site-packages"

script_dir=$(dirname $(realpath $0))
dist=$script_dir/dist_ios

# app xcframeworks
rm -rf $dist/site-xcframeworks
mkdir -p $dist/site-xcframeworks
cp -R $dist/python-xcframeworks/* $dist/site-xcframeworks

# convert site-packages to xcframeworks
if [ -n "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then

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
            "Frameworks/serious_python_darwin.framework/site-packages" \
            $dist/site-xcframeworks
    done

    rm -rf $dist/site-packages
    mkdir -p $dist/site-packages
    cp -R $tmp_dir/${archs[0]}/* $dist/site-packages

    # cleanup
    rm -rf "${tmp_dir}" >/dev/null
else
    echo "SERIOUS_PYTHON_SITE_PACKAGES is not set."
fi