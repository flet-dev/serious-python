version=${1:?}
python_version=${2:?}
dist=${3:?}

python_ios_dist_file="python-ios-dart-$python_version.tar.gz"
python_ios_dist_url="https://github.com/flet-dev/python-darwin/releases/download/v$python_version/$python_ios_dist_file"

rm -rf $dist
mkdir -p $dist

# download iOS dist
curl -LO $python_ios_dist_url
tar -xzf $python_ios_dist_file -C $dist
rm $python_ios_dist_file

if [ -n "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then

    . xcframework_utils.sh

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
            $dist/python-xcframeworks
    done

    rm -rf $dist/site-packages
    mkdir -p $dist/site-packages
    cp -R $tmp_dir/${archs[0]}/* $dist/site-packages

    # cleanup
    rm -rf "${tmp_dir}" >/dev/null
fi