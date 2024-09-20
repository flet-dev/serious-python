#PYTHON_XCFRAMEWORKS_ROOT=/Users/feodor/projects/flet-dev/serious-python/src/serious_python_darwin/darwin/dist_ios/frameworks
#PLATFORM_NAME="iphonesimulator"

find $PYTHON_XCFRAMEWORKS_ROOT -name "*.xcframework" | while read full_framework_path; do
    framework_relative_path=${full_framework_path#$PYTHON_XCFRAMEWORKS_ROOT/}
    framework_name=$(echo $framework_relative_path | cut -d "." -f 1)
    if [[ "$PLATFORM_NAME" == *"simulator" ]]; then
        slice="ios-arm64_x86_64-simulator"
    else
        slice="ios-arm64"
    fi
    install_framework "$full_framework_path/$slice/$framework_name.framework"
done