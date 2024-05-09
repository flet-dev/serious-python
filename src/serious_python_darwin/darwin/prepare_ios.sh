version=${1:?}
python_version=${2:?}
dist_ios=${3:?}

python_ios_dist_file="python-$python_version-ios.tar.gz"
python_ios_dist_url="" #"https://ci.appveyor.com/api/buildjobs/agifs86hui0ff3uu/artifacts/$python_ios_dist_file"
#python_ios_dist_url = "https://github.com/flet-dev/serious-python/releases/download/v#{s.version}/$PYTHON_IOS_DIST_FILE
 
rm -rf $dist_ios
mkdir -p $dist_ios

# copy or download iOS dist
if [ -n "$SERIOUS_PYTHON_IOS_DIST" ]; then
    cp -R "$SERIOUS_PYTHON_IOS_DIST"/* $dist_ios
else
    curl -LO $python_ios_dist_url
    tar -xzf $python_ios_dist_file -C $dist_ios
    rm $python_ios_dist_file
fi

if [ -n "$SERIOUS_PYTHON_IOS_SITE_PACKAGES" ]; then

    . xcframework_utils.sh

    
    tmp_dir=$(mktemp -d)

    cp -R $SERIOUS_PYTHON_IOS_SITE_PACKAGES/* $tmp_dir

    echo "Converting .dylibs to xcframeworks..."
    find "$tmp_dir/${archs[0]}" -name "*.$dylib_suffix" | while read full_dylib; do
        dylib_relative_path=${full_dylib#$tmp_dir/${archs[0]}/}
        create_xcframework_from_dylibs \
            "$tmp_dir/${archs[0]}" \
            "$tmp_dir/${archs[1]}" \
            "$tmp_dir/${archs[2]}" \
            $dylib_relative_path \
            $dist_ios/xcframeworks
    done

    rm -rf $dist_ios/site-packages
    mkdir -p $dist_ios/site-packages
    cp -R $tmp_dir/${archs[0]}/* $dist_ios/site-packages

    # cleanup
    rm -rf "${tmp_dir}" >/dev/null
fi