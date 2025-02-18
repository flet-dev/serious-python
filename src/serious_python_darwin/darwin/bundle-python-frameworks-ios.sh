echo "Bundle Python xcframeworks"

# modify Flutter packaging script to include user frameworks
if [ -n "$PODS_TARGET_SRCROOT" ]; then
    echo "modify Flutter packaging script to include user frameworks: $PODS_TARGET_SRCROOT"
    pods_runner_frameworks_script="$PODS_ROOT/Target Support Files/Pods-Runner/Pods-Runner-frameworks.sh"

    if ! grep -q "added by serious_python_darwin plugin" "$pods_runner_frameworks_script"; then
        echo "" >> $pods_runner_frameworks_script
        echo "PYTHON_XCFRAMEWORKS_ROOT=\x22$PODS_TARGET_SRCROOT/dist_ios/site-xcframeworks\x22" >> $pods_runner_frameworks_script
        cat $PODS_TARGET_SRCROOT/pods-runner-frameworks-addon.sh >> $pods_runner_frameworks_script
    fi
fi