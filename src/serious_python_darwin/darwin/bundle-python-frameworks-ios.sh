echo "Bundle Python xcframeworks"

# This path installs the stdlib / site-package extensions by copying the INNER
# .framework bundles out of each .xcframework (see pods-runner-frameworks-addon.sh).
# Xcode only writes an SDK-origin receipt — Signatures/<name>.xcframework-ios.signature
# in the IPA — for xcframeworks it consumes as a declared binary dependency, so
# frameworks installed this way arrive with no provenance record regardless of how
# well the source xcframework was signed. That is what Apple reports as
# `ITMS-91065: Missing signature`.
#
# `warning:` is the prefix Xcode surfaces in the build log and issue navigator.
echo "warning: serious_python: the CocoaPods iOS path copies inner .framework bundles and cannot produce SDK-origin XCFramework signature receipts. Use the Swift Package Manager path for App Store submissions."

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