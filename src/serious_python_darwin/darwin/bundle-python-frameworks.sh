echo "Bundle Python xcframeworks!"

pods_runner_frameworks_script="$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"

if ! grep -q "added by serious_python_darwin plugin" "$pods_runner_frameworks_script"; then
    echo "" >> $pods_runner_frameworks_script
    echo "PYTHON_XCFRAMEWORKS_ROOT=\x22$PODS_TARGET_SRCROOT/dist_ios/python-xcframeworks\x22" >> $pods_runner_frameworks_script
    cat $PODS_TARGET_SRCROOT/pods-runner-frameworks-addon.sh >> $pods_runner_frameworks_script
fi