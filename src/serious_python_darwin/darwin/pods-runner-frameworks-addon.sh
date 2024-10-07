# -- added by serious_python_darwin plugin --
# This file is appended to $PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh

# PYTHON_XCFRAMEWORKS_ROOT="{path}"
# PLATFORM_NAME="iphonesimulator"

find $PYTHON_XCFRAMEWORKS_ROOT -name "*.xcframework" | while read full_framework_path; do
    framework_relative_path=${full_framework_path#$PYTHON_XCFRAMEWORKS_ROOT/}
    framework_name=$(basename $framework_relative_path ".xcframework")
    if [[ "$PLATFORM_NAME" == *"simulator" ]]; then
        slice="ios-arm64_x86_64-simulator"
    else
        slice="ios-arm64"
    fi
    echo "install_framework $full_framework_path/$slice/$framework_name.framework"
    install_framework "$full_framework_path/$slice/$framework_name.framework"
done