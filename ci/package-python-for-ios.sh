#!/bin/bash
set -eu

python_apple_support_root=${1:?}
python_version=${2:?}

script_dir=$(dirname $(realpath $0))

. $script_dir/../src/serious_python_darwin/darwin/xcframework_utils.sh

# build short Python version
read python_version_major python_version_minor < <(echo $python_version | sed -E 's/^([0-9]+)\.([0-9]+).*/\1 \2/')
python_version_short=$python_version_major.$python_version_minor

# create build directory
build_dir=build/python-$python_version
rm -rf $build_dir
mkdir -p $build_dir
build_dir=$(realpath $build_dir)

# create dist directory
dist_dir=dist/python-$python_version
rm -rf $dist_dir
mkdir -p $dist_dir
dist_dir=$(realpath $dist_dir)

frameworks_dir=$build_dir/xcframeworks
stdlib_dir=$build_dir/python-stdlib
mkdir -p $frameworks_dir
mkdir -p $stdlib_dir

# copy Python.xcframework
rsync -av $python_apple_support_root/support/$python_version_short/iOS/Python.xcframework $frameworks_dir
cp $script_dir/module.modulemap $frameworks_dir/Python.xcframework/ios-arm64/Headers
cp $script_dir/module.modulemap $frameworks_dir/Python.xcframework/ios-arm64_x86_64-simulator/Headers

# copy stdlibs
for arch in "${archs[@]}"; do
    rsync -av --exclude-from=$script_dir/python-darwin-distro.exclude $python_apple_support_root/install/iOS/$arch/python-*/lib/python$python_version_short/* $stdlib_dir/$arch
done

echo "Converting lib-dynload to xcframeworks..."
find "$stdlib_dir/${archs[0]}/lib-dynload" -name "*.$dylib_suffix" | while read full_dylib; do
    dylib_relative_path=${full_dylib#$stdlib_dir/${archs[0]}/lib-dynload/}
    create_xcframework_from_dylibs \
        "$stdlib_dir/${archs[0]}/lib-dynload" \
        "$stdlib_dir/${archs[1]}/lib-dynload" \
        "$stdlib_dir/${archs[2]}/lib-dynload" \
        $dylib_relative_path \
        $frameworks_dir
    #break # run for one lib only - for tests
done

mv $stdlib_dir/${archs[0]}/* $stdlib_dir

# cleanup
for arch in "${archs[@]}"; do
    find $stdlib_dir/$arch -name _sysconfigdata__*.py -exec cp {} $stdlib_dir \;
    rm -rf $stdlib_dir/$arch
done
rm -rf $stdlib_dir/lib-dynload

# compile stdlib
cd $stdlib_dir
python -m compileall -b .
find . \( -name '*.so' -or -name "*.$dylib_suffix" -or -name '*.py' -or -name '*.typed' \) -type f -delete
rm -rf __pycache__
rm -rf **/__pycache__
cd -

# final archive
tar -czf $dist_dir/python-$python_version-ios.tar.gz -C $build_dir .