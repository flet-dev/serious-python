#!/bin/bash
set -eu

archs=("iphoneos.arm64" "iphonesimulator.arm64" "iphonesimulator.x86_64")

python_apple_support_root=${1:?}
python_version=${2:?}

script_dir=$(dirname $(realpath $0))

# build short Python version
read python_version_major python_version_minor < <(echo $python_version | sed -E 's/^([0-9]+)\.([0-9]+).*/\1 \2/')
python_version_short=$python_version_major.$python_version_minor

# create build directory
build_dir=build/python-$python_version_short
rm -rf $build_dir
mkdir -p $build_dir
build_dir=$(realpath $build_dir)

# create dist directory
dist_dir=dist/python-$python_version_short
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
    rsync -av --exclude-from=$script_dir/python-ios-distro.exclude $python_apple_support_root/install/iOS/$arch/python-*/lib/python$python_version_short/* $stdlib_dir/$arch
done

create_plist() {
    name=$1
    identifier=$2
    plist_file=$3

    cat > $plist_file << PLIST_TEMPLATE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>$identifier</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>12.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
PLIST_TEMPLATE
}

# convert lib-dynloads to xcframeworks
create_xcframework_from_dylibs() {
    iphone_dir=$1
    simulator_arm64_dir=$2
    simulator_x86_64_dir=$3
    dylib_relative_path=$4
    out_dir=$5

    tmp_dir=$(mktemp -d)
    pushd -- "${tmp_dir}" >/dev/null

    echo "Creating framework for $dylib_relative_path"
    dylib_without_ext=$(echo $dylib_relative_path | cut -d "." -f 1)
    framework=$(echo $dylib_without_ext | tr "/" "_")
    framework_identifier=${framework//_/-}

    # creating "iphoneos" framework
    fd=iphoneos/$framework.framework
    mkdir -p $fd
    cp "$iphone_dir/$dylib_without_ext".*.dylib $fd/$framework
    install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework
    create_plist $framework "org.python.$framework_identifier" $fd/Info.plist

    # creating "iphonesimulator" framework
    fd=iphonesimulator/$framework.framework
    mkdir -p $fd
    lipo -create \
        "$simulator_arm64_dir/$dylib_without_ext".*.dylib \
        "$simulator_x86_64_dir/$dylib_without_ext".*.dylib \
        -output $fd/$framework
    install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework
    create_plist $framework "org.python.$framework_identifier" $fd/Info.plist

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
find . \( -name '*.so' -or -name '*.dylib' -or -name '*.py' -or -name '*.typed' \) -type f -delete
rm -rf __pycache__
rm -rf **/__pycache__
cd -

# final archive
tar -czf $dist_dir/python-$python_version_short-ios.tar.gz -C $build_dir .