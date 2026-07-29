script_dir=$(cd "$(dirname "$0")" && pwd -P)

# Provider-signature + provider-integrity checks (see xcframework_verify.sh).
# Sourced unconditionally so both the iOS and macOS branches can use it.
source $script_dir/xcframework_verify.sh

# App sources are arch- and platform-independent; stage them as a bare `app/`
# resource bundle into BOTH dist trees, regardless of whether site-packages
# exist (an app may have no pip dependencies). The per-target resource bundle
# (dist_ios / dist_macos) picks the right one at build time. This MUST run
# outside the SERIOUS_PYTHON_SITE_PACKAGES guard below — otherwise a
# dependency-free app never gets bundled and the runtime can't find main.py.
if [[ -n "$SERIOUS_PYTHON_APP" && -d "$SERIOUS_PYTHON_APP" ]]; then
    for app_dist in "$script_dir/dist_ios" "$script_dir/dist_macos"; do
        rm -rf "$app_dist/app"
        mkdir -p "$app_dist/app"
        rsync -a --exclude '.pod' "$SERIOUS_PYTHON_APP/" "$app_dist/app/"
    done
fi

if [[ -n "$SERIOUS_PYTHON_SITE_PACKAGES" && -d "$SERIOUS_PYTHON_SITE_PACKAGES" ]]; then

    if [[ -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphoneos.arm64" && -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphonesimulator.arm64" && -d "$SERIOUS_PYTHON_SITE_PACKAGES/iphonesimulator.x86_64" ]]; then

        echo "Sync iOS xcframeworks and site-packages"
        dist=$script_dir/dist_ios

        source $script_dir/xcframework_utils.sh

        tmp_dir=$(mktemp -d)
        # Locally generated frameworks are built and mutated HERE, in their own
        # directory, never alongside the provider-built ones. Every app-specific
        # rewrite below (bundle ids, install names, ad-hoc re-sign) is confined
        # to this tree; the provider artifacts are merged in afterwards,
        # byte-for-byte, and are never opened for writing.
        local_xcframeworks=$(mktemp -d)

        cp -R $SERIOUS_PYTHON_SITE_PACKAGES/* $tmp_dir

        echo "Converting dylibs to xcframeworks..."
        # Process BOTH .so (Python C-extensions) and .dylib (ctypes-loaded shared libs).
        for _sp_ext in so dylib; do
        # -type f: only match regular files, skipping SONAME symlinks, so only real Mach-O files are converted.
        find "$tmp_dir/${archs[0]}" -name "*.$_sp_ext" -type f | while read full_dylib; do
            dylib_relative_path=${full_dylib#$tmp_dir/${archs[0]}/}
            create_xcframework_from_dylibs \
                "$tmp_dir/${archs[0]}" \
                "$tmp_dir/${archs[1]}" \
                "$tmp_dir/${archs[2]}" \
                $dylib_relative_path \
                "$_sp_ext" \
                "Frameworks/serious_python_darwin.framework/python.bundle/site-packages" \
                $local_xcframeworks
        done
        done

        # Namespace the LOCALLY BUILT frameworks' CFBundleIdentifiers under the
        # host app's bundle id (see xcframework_utils.sh). These are created
        # moments ago from this app's own wheels; nobody has signed them, so
        # editing their plists invalidates nothing.
        #
        # This deliberately no longer touches Python.xcframework or the stdlib
        # extension frameworks. Those arrive already signed by their provider,
        # and a plist rewrite destroys that signature -- which is what made the
        # IPA's Signatures/ receipts report `signed = false` and produced
        # ITMS-91065. They now carry stable `dev.flet.python.*` identifiers
        # assigned upstream in python-build, so there is nothing left to fix
        # here anyway.
        if [[ -n "${SERIOUS_PYTHON_BUNDLE_ID:-}" ]]; then
            echo "Namespacing framework bundle identifiers under $SERIOUS_PYTHON_BUNDLE_ID"
            rewrite_framework_bundle_ids "$local_xcframeworks" "$SERIOUS_PYTHON_BUNDLE_ID" || exit 1
        fi

        # After every .so/.dylib is framework-ized, reconcile the Mach-O
        # install names so the interdependent @rpath refs point at the new
        # framework paths (serious-python #223). Without this, dyld cannot
        # resolve e.g. @rpath/libarrow.dylib at launch and the app crashes
        # before Python starts.
        # A reconcile failure (e.g. a Mach-O with no header space to grow a load
        # command, or a signing error) would otherwise ship an app that crashes
        # at launch -- abort the build instead. sync_site_packages.sh has no
        # set -e; prepare_spm.sh runs it under set -euo pipefail, so a non-zero
        # exit here fails `flet build` loudly.
        #
        # The exclude argument still names the provider stdlib directory. It is
        # now belt and braces -- $local_xcframeworks holds only locally built
        # frameworks -- but it keeps the guarantee explicit: this pass rewrites
        # Mach-O headers and re-signs ad-hoc, and must never reach a provider
        # binary.
        reconcile_framework_install_names "$local_xcframeworks" "$dist/python-xcframeworks" || exit 1

        # Assemble the staging directory: provider frameworks first, copied
        # verbatim, then the locally built ones merged over the top (a name
        # collision resolves to the local build, as it always has). The rm -rf
        # in the loop is what makes that an overwrite rather than a `cp -R`
        # merge, which would leave the provider's files behind inside it.
        rm -rf $dist/site-xcframeworks
        mkdir -p $dist/site-xcframeworks
        cp -R $dist/python-xcframeworks/* $dist/site-xcframeworks
        for _local_xcf in "$local_xcframeworks"/*.xcframework; do
            [ -d "$_local_xcf" ] || continue
            rm -rf "$dist/site-xcframeworks/$(basename "$_local_xcf")"
            cp -R "$_local_xcf" "$dist/site-xcframeworks/"
        done

        rm -rf $dist/site-packages
        mkdir -p $dist/site-packages
        cp -R $tmp_dir/${archs[0]}/* $dist/site-packages

        # cleanup
        rm -rf "${tmp_dir}" "${local_xcframeworks}" >/dev/null

        # The provider artifacts must be bit-identical to what was extracted in
        # prepare_ios.sh, both where they live and in the copies just staged.
        spv_manifest_check "$dist/.provider-manifests/xcframeworks.sha256" \
            "$dist/xcframeworks" "dist_ios/xcframeworks" || exit 1
        spv_manifest_check "$dist/.provider-manifests/python-xcframeworks.sha256" \
            "$dist/python-xcframeworks" "dist_ios/python-xcframeworks" || exit 1
        spv_manifest_check "$dist/.provider-manifests/python-xcframeworks.sha256" \
            "$dist/site-xcframeworks" "dist_ios/site-xcframeworks (provider subset)" || exit 1
        spv_verify_provider "$dist/xcframeworks" "$dist/python-xcframeworks" || exit 1

    else

        echo "Sync macOS xcframeworks and site-packages"
        dist=$script_dir/dist_macos

        mkdir -p $dist/site-packages
        # Exclude the .pod symlink created by symlink_pod.sh — it points at
        # this plugin's source tree. If it lands in dist_macos/site-packages,
        # CocoaPods packages it into the production .app, where macOS
        # LaunchServices finds the embedded Python.app inside the symlinked
        # Python.xcframework and tries to launch it (DYLD failure, repeated
        # crash report popups), and `flet build`'s copy_tree follows the
        # symlink into a code-signed source tree and hits EPERM on every
        # file. .pod is only needed by package_command.dart at packaging
        # time to invoke this sync script; it does not belong in the bundle.
        rsync -av --delete --exclude '.pod' "$SERIOUS_PYTHON_SITE_PACKAGES/" "$dist/site-packages/"

        # macOS has no framework-ization step -- its .so's load flat from the
        # resource tree -- so nothing here should ever touch the provider
        # xcframeworks. Assert it rather than assume it.
        spv_manifest_check "$dist/.provider-manifests/xcframeworks.sha256" \
            "$dist/xcframeworks" "dist_macos/xcframeworks" || exit 1
        spv_verify_provider "$dist/xcframeworks" || exit 1
    fi
fi
