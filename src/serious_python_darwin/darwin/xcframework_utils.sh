archs=("iphoneos.arm64" "iphonesimulator.arm64" "iphonesimulator.x86_64")

dylib_ext=so

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
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>13.0</string>
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
    ext=${5:-$dylib_ext}
    origin_prefix=$6
    out_dir=$7

    dylib_tmp_dir=$(mktemp -d)
    pushd -- "${dylib_tmp_dir}" >/dev/null

    echo "Creating framework for $dylib_relative_path"
    dylib_without_ext=$(echo $dylib_relative_path | cut -d "." -f 1)
    framework=$(echo $dylib_without_ext | tr "/" ".")
    framework_identifier=${framework//_/-}
    while [[ $framework_identifier == -* ]]; do
        framework_identifier=${framework_identifier#-}
    done
    framework_identifier=${framework_identifier:-framework}

    # If neither simulator slice has this lib, leave the file untouched rather
    # than fail `lipo` on an empty input (e.g. a device-only artifact). It then
    # ships as-is in the flat base, exactly as before this conversion existed.
    if [ -z "$(find "$simulator_arm64_dir" "$simulator_x86_64_dir" \
                    \( -path "*/$dylib_without_ext.*.$ext" -o -path "*/$dylib_without_ext.$ext" \) \
                    -type f 2>/dev/null | head -1)" ]; then
        echo "  no simulator slice for $dylib_relative_path; leaving as-is"
        popd >/dev/null
        rm -rf "${dylib_tmp_dir}" >/dev/null
        return
    fi

    # creating "iphoneos" framework
    fd=iphoneos/$framework.framework
    mkdir -p $fd
    mv "$iphone_dir/$dylib_relative_path" $fd/$framework
    echo "Frameworks/$framework.framework/$framework" > "$iphone_dir/$dylib_without_ext.fwork"
    if [ "$ext" = "so" ]; then install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework; fi
    create_plist $framework "org.python.$framework_identifier" $fd/Info.plist
    echo "$origin_prefix/$dylib_without_ext.fwork" > $fd/$framework.origin

    # creating "iphonesimulator" framework
    fd=iphonesimulator/$framework.framework
    mkdir -p $fd
    lipo -create \
        $(find "$simulator_arm64_dir" -path "$simulator_arm64_dir/$dylib_without_ext.*.$ext" -o -path "$simulator_arm64_dir/$dylib_without_ext.$ext") \
        $(find "$simulator_x86_64_dir" -path "$simulator_x86_64_dir/$dylib_without_ext.*.$ext" -o -path "$simulator_x86_64_dir/$dylib_without_ext.$ext") \
        -output $fd/$framework
    find "$simulator_arm64_dir" -path "$simulator_arm64_dir/$dylib_without_ext.*.$ext" -o -path "$simulator_arm64_dir/$dylib_without_ext.$ext" -delete
    find "$simulator_x86_64_dir" -path "$simulator_x86_64_dir/$dylib_without_ext.*.$ext" -o -path "$simulator_x86_64_dir/$dylib_without_ext.$ext" -delete
    if [ "$ext" = "so" ]; then install_name_tool -id @rpath/$framework.framework/$framework $fd/$framework; fi
    create_plist $framework "org.python.$framework_identifier" $fd/Info.plist
    echo "$origin_prefix/$dylib_without_ext.fwork" > $fd/$framework.origin

    # merge frameworks info xcframework
    xcodebuild -create-xcframework \
        -framework "iphoneos/$framework.framework" \
        -framework "iphonesimulator/$framework.framework" \
        -output $out_dir/$framework.xcframework

    # cleanup
    popd >/dev/null
    rm -rf "${dylib_tmp_dir}" >/dev/null
}