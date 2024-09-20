echo "HELLO! HELLO!!!"
#ls $CODESIGNING_FOLDER_PATH/../../XCFrameworkIntermediates/serious_python_darwin
echo $TARGET_NAME
ls $PODS_TARGET_SRCROOT

pods_runner_frameworks_script="$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"

echo "PYTHON_XCFRAMEWORKS_ROOT=\x22$PODS_TARGET_SRCROOT/dist_ios/python-xcframeworks\x22" >> $pods_runner_frameworks_script
cat $PODS_TARGET_SRCROOT/bundle-addon.sh >> $pods_runner_frameworks_script

#echo "install_framework \x22$PODS_TARGET_SRCROOT/dist_ios/frameworks/numpy._core._multiarray_tests.framework\x22" >> "$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"

# install_framework "${PODS_XCFRAMEWORKS_BUILD_DIR}/serious_python_darwin/Python.framework"
#echo "install_xcframework \x22$PODS_TARGET_SRCROOT/dist_ios/frameworks/zlib.xcframework\x22 \x22$TARGET_NAME\x22 \x22framework\x22 \x22ios-arm64\x22 \x22ios-arm64_x86_64-simulator\x22" >> "$PODS_ROOT/Target Support Files/$TARGET_NAME/$TARGET_NAME-xcframeworks.sh"
#ls -alR $PODS_XCFRAMEWORKS_BUILD_DIR
#cat "$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"
#cp -r /Users/feodor/projects/flet-dev/serious-python/src/serious_python_darwin/darwin/dist_ios/frameworks/numpy._core._multiarray_tests.framework $CODESIGNING_FOLDER_PATH/../../XCFrameworkIntermediates/serious_python_darwin