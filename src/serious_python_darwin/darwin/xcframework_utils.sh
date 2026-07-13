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

# Reconcile install names across the newly-created site-package frameworks.
#
# create_xcframework_from_dylibs renames each lib to a framework named by its
# dotted relative path (opt/lib/libarrow.dylib -> opt.lib.libarrow.framework/
# opt.lib.libarrow), but leaves the Mach-O install-id and every interdependent
# @rpath reference at their ORIGINAL bare names (e.g. @rpath/libarrow.dylib):
# it only rewrites the install-id, and only for ext=so. dyld links every one of
# these frameworks at app launch (each is a Package.swift binaryTarget the
# plugin depends on), so a bare @rpath/libarrow.dylib resolves to
# Frameworks/libarrow.dylib -- which does not exist -- and the app crashes
# BEFORE Python starts. See serious-python #223.
#
# This pass makes the install names match the framework layout:
#   1. set every framework binary's own install-id to @rpath/<fw>.framework/<fw>
#   2. rewrite every dep that pointed at a sibling's OLD id to that sibling's
#      framework path, so interdependent libs (libarrow_python -> libarrow, or a
#      C-extension -> its bundled .dylib) resolve at launch.
# Only the frameworks created from site-packages are touched; the Python /
# stdlib xcframeworks (passed as $2) are already correct and left untouched.
reconcile_framework_install_names() {
    local xcframeworks_dir=$1
    local exclude_dir=$2

    local -a map_old=()
    local -a map_new=()

    # Pass 1: fix each framework's own install-id; record old->new for deps.
    local xcf fw newid bin oldid raw
    for xcf in "$xcframeworks_dir"/*.xcframework; do
        [ -d "$xcf" ] || continue
        fw=$(basename "$xcf" .xcframework)
        [ -n "$exclude_dir" ] && [ -e "$exclude_dir/$fw.xcframework" ] && continue
        newid="@rpath/$fw.framework/$fw"
        oldid=""
        for bin in "$xcf"/*/"$fw.framework/$fw"; do
            [ -f "$bin" ] || continue
            if [ -z "$oldid" ]; then
                # Buffer otool output before filtering: piping otool straight
                # into `head -1` lets head close the pipe early, and the SIGPIPE
                # race intermittently drops the first read (empty oldid), which
                # cascades into a shifted/short map.
                raw=$(otool -D "$bin" 2>/dev/null)
                oldid=$(printf '%s\n' "$raw" | grep -v ':$' | grep -vi 'Architectures in' | head -1 | sed 's/^[[:space:]]*//')
            fi
            install_name_tool -id "$newid" "$bin" 2>/dev/null || true
        done
        if [ -n "$oldid" ] && [ "$oldid" != "$newid" ]; then
            map_old+=("$oldid")
            map_new+=("$newid")
        fi
    done

    # Pass 2: rewrite interdependent refs to framework paths, then re-sign
    # (install_name_tool invalidates the ad-hoc signature).
    local i n=${#map_old[@]}
    for xcf in "$xcframeworks_dir"/*.xcframework; do
        [ -d "$xcf" ] || continue
        fw=$(basename "$xcf" .xcframework)
        [ -n "$exclude_dir" ] && [ -e "$exclude_dir/$fw.xcframework" ] && continue
        for bin in "$xcf"/*/"$fw.framework/$fw"; do
            [ -f "$bin" ] || continue
            i=0
            while [ $i -lt $n ]; do
                # no-op if this binary does not reference map_old[i]
                install_name_tool -change "${map_old[$i]}" "${map_new[$i]}" "$bin" 2>/dev/null || true
                i=$((i+1))
            done
            codesign --force --sign - "$bin" >/dev/null 2>&1 || true
        done
    done
}