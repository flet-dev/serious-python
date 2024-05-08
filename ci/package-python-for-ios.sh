#!/bin/bash
set -eu

archs=("iphoneos.arm64" "iphonesimulator.arm64" "iphonesimulator.x86_64")

python_apple_support_root=${1:?}
python_version=${2:?}

script_dir=$(dirname $(realpath $0))

# build short Python version
read python_version_major python_version_minor < <(echo $python_version | sed -E 's/^([0-9]+)\.([0-9]+).*/\1 \2/')
python_version_short=$python_version_major.$python_version_minor

# create dist directory
dist=dist/python-$python_version_short
rm -rf $dist
mkdir -p $dist
dist_dir=$(realpath $dist)
frameworks_dir=$dist_dir/xcframeworks
stdlib_dir=$dist_dir/python-stdlib
mkdir -p $frameworks_dir
mkdir -p $stdlib_dir

# copy Python.xcframework
rsync -av $python_apple_support_root/support/$python_version_short/iOS/Python.xcframework $frameworks_dir
cp $script_dir/module.modulemap $frameworks_dir/Python.xcframework/ios-arm64/Headers
cp $script_dir/module.modulemap $frameworks_dir/Python.xcframework/ios-arm64_x86_64-simulator/Headers

# copy stdlibs
for arch in "${archs[@]}"; do
    rsync -av --exclude-from=$script_dir/python-ios-distro.exclude $python_apple_support_root/install/iOS/$arch/python-$python_version/lib/python$python_version_short/* $stdlib_dir/$arch
done

# convert lib-dynloads to xcframeworks
create_xcframework_from_dylibs() {
    dylib_relative_path=$1
    arch_dir_template=$2
    out_dir=$3

    tmp_dir=$(mktemp -d)
    pushd -- "${tmp_dir}" >/dev/null

    echo "Creating framework for $dylib_relative_path"
    dylib_without_ext=$(echo $dylib_relative_path | cut -d "." -f 1)
    framework=$(echo $dylib_without_ext | tr "/" "_")
    framework_identifier=${framework//_/-}

    # creating "iphoneos" framework
    fd=iphoneos/$framework.framework
    mkdir -p $fd
    arch_dir=$(echo $arch_dir_template | sed "s#{arch}#iphoneos.arm64#")
    cp "$arch_dir/$dylib_without_ext".*.dylib $fd/$framework
    install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework
    cp $script_dir/dylib-Info-template.plist $fd/Info.plist
    plutil -replace CFBundleName -string $framework $fd/Info.plist
    plutil -replace CFBundleExecutable -string $framework $fd/Info.plist
    plutil -replace CFBundleIdentifier -string org.python.$framework_identifier $fd/Info.plist

    # creating "iphonesimulator" framework
    fd=iphonesimulator/$framework.framework
    mkdir -p $fd
    arch_arm64_dir=$(echo $arch_dir_template | sed "s#{arch}#iphonesimulator.arm64#")
    arch_x86_64_dir=$(echo $arch_dir_template | sed "s#{arch}#iphonesimulator.x86_64#")
    lipo -create \
        "$arch_arm64_dir/$dylib_without_ext".*.dylib \
        "$arch_x86_64_dir/$dylib_without_ext".*.dylib \
        -output $fd/$framework
    install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework
    cp $script_dir/dylib-Info-template.plist $fd/Info.plist
    plutil -replace CFBundleName -string $framework $fd/Info.plist
    plutil -replace CFBundleExecutable -string $framework $fd/Info.plist
    plutil -replace CFBundleIdentifier -string org.python.$framework_identifier $fd/Info.plist

    # merge frameworks info xcframework
    xcodebuild -create-xcframework \
        -framework "iphoneos/$framework.framework" \
        -framework "iphonesimulator/$framework.framework" \
        -output $out_dir/$framework.xcframework

    # cleanup
    popd >/dev/null
    rm -rf "${tmp_dir}" >/dev/null
}

echo "Converting lib-dynload to xcframeworks..."
find "$stdlib_dir/${archs[0]}/lib-dynload" -name "*.dylib" | while read full_dylib; do
    dylib_relative_path=${full_dylib#$stdlib_dir/${archs[0]}/lib-dynload/}
    create_xcframework_from_dylibs \
        $dylib_relative_path \
        "$stdlib_dir/{arch}/lib-dynload" \
        $frameworks_dir
    #break # run for one lib only - for tests
done

# compile, clean stdlib
cd $stdlib_dir/${archs[0]}
python -m compileall -b .
find . \( -name '*.so' -or -name '*.dylib' -or -name '*.py' -or -name '*.typed' \) -type f -delete
rm -rf __pycache__
rm -rf **/__pycache__
cd -
mv $stdlib_dir/${archs[0]}/* $stdlib_dir

# cleanup
for arch in "${archs[@]}"; do
    rm -rf $stdlib_dir/$arch
done
rm -rf $stdlib_dir/lib-dynload

# final archive
#tar -czf dist/python-$python_version_short-ios.tar.gz -C $dist_dir .