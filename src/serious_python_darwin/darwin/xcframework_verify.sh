#!/usr/bin/env bash
#
# Consumer-side integrity checks for the XCFrameworks serious_python does NOT
# build: Python.xcframework and the stdlib extension frameworks from
# flet-dev/python-build, and dart_bridge.xcframework from flet-dev/dart-bridge.
#
# WHY
#   Xcode writes an SDK-origin receipt for every XCFramework an app links
#   against into the IPA's `Signatures/` directory, reporting whether the
#   XCFramework AS SHIPPED BY ITS PROVIDER was signed and carried a secure
#   timestamp. Signing the app does not fill that in, and any edit to a file
#   inside a signed XCFramework destroys it — which is exactly what this plugin
#   used to do when it rewrote CFBundleIdentifier in the provider bundles.
#
#   So this file exists to answer two questions at each staging step:
#     1. does the provider signature still verify?  (spv_verify_provider)
#     2. did anything inside the provider bundles change?  (spv_manifest_*)
#
#   Question 2 matters even while the upstream artifacts are still unsigned: the
#   digest manifest catches a reintroduced mutation immediately, rather than in
#   an App Store rejection three releases later.
#
# MODE — SERIOUS_PYTHON_VERIFY_PROVIDER_SIGNATURES
#   warn     (default) report problems, do not fail the build
#   require  a missing or invalid provider signature fails the build
#   off      skip signature checks entirely
#
#   The default is `warn` because a consumer may pin an older, pre-signing
#   python-build / dart-bridge release through SERIOUS_PYTHON_BUILD_DATE or
#   DART_BRIDGE_VERSION, and that must keep building. serious_python's own CI
#   sets `require`.
#
#   Digest-manifest checks are NOT gated by this: they cover code in this repo,
#   which is always expected to leave provider bundles untouched.
#
# SERIOUS_PYTHON_EXPECTED_TEAM_ID
#   When set, the provider signature's TeamIdentifier must match it.
#
# Written to POSIX sh so the podspec's prepare_command (run through /bin/sh) can
# source it as-is.

spv_mode() { echo "${SERIOUS_PYTHON_VERIFY_PROVIDER_SIGNATURES:-warn}"; }

spv_note() { echo "provider-verify: $*"; }

# Report one problem.
#
# In `require` mode every problem is printed and the caller fails. In `warn` mode
# only the first few are printed and the rest are counted: a build against a
# pre-signing python-build release has ~57 unsigned xcframeworks, and 57
# identical lines in every `flet build` teaches people to ignore the message.
# The summary line at the end always reports the true total.
spv_bad() {
    _spv_problems=$((${_spv_problems:-0} + 1))
    if [ "$(spv_mode)" = "require" ] || [ "$_spv_problems" -le 3 ]; then
        echo "provider-verify: $*" >&2
    elif [ "$_spv_problems" -eq 4 ]; then
        echo "provider-verify: ... further problems suppressed;" \
             "set SERIOUS_PYTHON_VERIFY_PROVIDER_SIGNATURES=require to see them all" >&2
    fi
    # Written as an `if` rather than `[ ] && return 1` so a caller running under
    # `set -e` is not aborted by the false test in `warn` mode.
    if [ "$(spv_mode)" = "require" ]; then
        return 1
    fi
    return 0
}

# Emit the xcframework paths a root refers to. A root is either an
# `*.xcframework` itself or a directory containing some.
spv_each() {
    case "$1" in
        *.xcframework)
            if [ -d "$1" ]; then printf '%s\n' "$1"; fi
            ;;
        *)
            for _spv_x in "$1"/*.xcframework; do
                if [ -d "$_spv_x" ]; then printf '%s\n' "$_spv_x"; fi
            done
            ;;
    esac
    return 0
}

# Emit the per-slice .framework bundles inside an xcframework.
#
# Globbed rather than derived from the xcframework's name: stage_spm.sh stages
# Python.xcframework as Python-<platform>.xcframework, and a name-keyed lookup
# would quietly find nothing there — turning "this slice is unsigned" into "there
# was nothing to check".
spv_slice_frameworks() {
    for _spv_slice in "$1"/*/; do
        [ -d "$_spv_slice" ] || continue
        for _spv_fw in "$_spv_slice"*.framework; do
            if [ -d "$_spv_fw" ]; then printf '%s\n' "$_spv_fw"; fi
        done
    done
    return 0
}

# Assert one signed bundle carries a usable provider signature: verifiable, not
# ad-hoc, securely timestamped, and (when configured) the expected team.
spv_assert_signature() {
    _spv_t=$1

    # `codesign -dv` rather than probing for a _CodeSignature directory: a
    # versioned macOS bundle keeps it at Versions/<name>/_CodeSignature and the
    # version directory is not always "A" (CPython uses e.g. Versions/3.14).
    if ! codesign -dv "$_spv_t" >/dev/null 2>&1; then
        spv_bad "$_spv_t: not signed at all;" \
                "its IPA receipt will report signed = false" || return 1
        return 0
    fi

    if ! _spv_out=$(codesign --verify --strict --verbose=4 "$_spv_t" 2>&1); then
        spv_bad "$_spv_t: provider signature does not verify: $_spv_out" || return 1
        return 0
    fi

    _spv_info=$(codesign -dvvv "$_spv_t" 2>&1) || _spv_info=""

    if printf '%s\n' "$_spv_info" | grep -q '^Signature=adhoc'; then
        spv_bad "$_spv_t: ad-hoc signature, not a provider signature" || return 1
        return 0
    fi

    if ! printf '%s\n' "$_spv_info" | grep -q '^Timestamp='; then
        spv_bad "$_spv_t: no secure timestamp;" \
                "its IPA receipt will report isSecureTimestamp = false" || return 1
        return 0
    fi

    if [ -n "${SERIOUS_PYTHON_EXPECTED_TEAM_ID:-}" ]; then
        _spv_team=$(printf '%s\n' "$_spv_info" | sed -n 's/^TeamIdentifier=//p' | head -1)
        if [ "$_spv_team" != "$SERIOUS_PYTHON_EXPECTED_TEAM_ID" ]; then
            spv_bad "$_spv_t: TeamIdentifier '$_spv_team' !=" \
                    "expected '$SERIOUS_PYTHON_EXPECTED_TEAM_ID'" || return 1
            return 0
        fi
    fi
    return 0
}

# Verify the provider signature on every xcframework under the given roots —
# BOTH the outer bundle and each slice's inner .framework.
#
# Both layers matter. An XCFramework whose outer bundle is signed but whose inner
# frameworks are not produces an IPA receipt reading `signed = true` but
# `isSecureTimestamp = false`; every slice of an XCFramework Apple's App Store
# scan accepts is signed in its own right. Checking only the outer seal would let
# that regression reach a submission unnoticed, which is exactly how it reached
# one before.
#
# Roots must name PROVIDER artifacts only. Frameworks this plugin generates from
# the app's own site-packages are built locally, carry an ad-hoc signature, and
# are correctly excluded — requiring a provider identity on them would be wrong.
spv_verify_provider() {
    _spv_mode=$(spv_mode)
    if [ "$_spv_mode" = "off" ]; then
        return 0
    fi

    _spv_status=0
    _spv_count=0
    _spv_slices=0
    _spv_problems=0
    for _spv_root in "$@"; do
        [ -e "$_spv_root" ] || continue
        for _spv_xcf in $(spv_each "$_spv_root"); do
            _spv_count=$((_spv_count + 1))

            # Outer bundle. Checked by file rather than via codesign so an
            # entirely unsigned XCFramework reports the useful message.
            if [ ! -f "$_spv_xcf/_CodeSignature/CodeResources" ]; then
                spv_bad "$_spv_xcf: no provider signature (unsigned XCFramework);" \
                        "its IPA receipt will report signed = false" || _spv_status=1
                continue
            fi
            spv_assert_signature "$_spv_xcf" || _spv_status=1

            # Each slice's inner framework, in its own right.
            for _spv_inner in $(spv_slice_frameworks "$_spv_xcf"); do
                _spv_slices=$((_spv_slices + 1))
                spv_assert_signature "$_spv_inner" || _spv_status=1
            done
        done
    done

    if [ "$_spv_count" -eq 0 ]; then
        # An empty tree must never read as "everything passed".
        spv_bad "no *.xcframework found under: $*" || _spv_status=1
    elif [ "$_spv_problems" -gt 0 ]; then
        spv_note "$_spv_problems signature problem(s) across $_spv_count provider" \
                 "xcframework(s) and $_spv_slices slice framework(s); the resulting IPA" \
                 "will report them as unsigned or without a secure timestamp"
    else
        spv_note "provider signatures verified on $_spv_count xcframework(s)" \
                 "and $_spv_slices slice framework(s)"
    fi
    return $_spv_status
}

# Record a digest manifest of everything under $2, keyed on paths relative to
# it, so the same manifest can be checked against a copy staged elsewhere.
#
# Symlinks are recorded by target, not followed: the macOS Python.framework is a
# versioned bundle whose symlinks are part of what codesign seals.
spv_manifest_record() {
    _spv_out=$1
    _spv_root=$2
    [ -d "$_spv_root" ] || return 0

    mkdir -p "$(dirname "$_spv_out")"
    {
        ( cd "$_spv_root" && find . -type f -exec shasum -a 256 {} + )
        ( cd "$_spv_root" && find . -type l -exec sh -c \
            'for l; do printf "symlink:%s  %s\n" "$(readlink "$l")" "$l"; done' _ {} + )
    } | LC_ALL=C sort > "$_spv_out"
    spv_note "recorded $(wc -l < "$_spv_out" | tr -d ' ') digests for $_spv_root"
}

# Check that every path recorded in $1 still exists under $2 with the same
# content. Extra files under $2 are ignored, so one manifest of the provider
# stdlib frameworks also validates the merged directory they are staged into
# alongside locally generated ones.
#
# Always fatal. Nothing in this repo is allowed to modify a provider bundle, so
# a mismatch is a bug here, not a property of whatever upstream release is
# pinned.
spv_manifest_check() {
    _spv_manifest=$1
    _spv_root=$2
    _spv_label=${3:-$_spv_root}

    [ -f "$_spv_manifest" ] || { spv_note "no manifest at $_spv_manifest; skipping check"; return 0; }
    [ -d "$_spv_root" ] || { echo "provider-verify: $_spv_root missing" >&2; return 1; }

    _spv_actual=$(mktemp)
    {
        ( cd "$_spv_root" && find . -type f -exec shasum -a 256 {} + )
        ( cd "$_spv_root" && find . -type l -exec sh -c \
            'for l; do printf "symlink:%s  %s\n" "$(readlink "$l")" "$l"; done' _ {} + )
    } | LC_ALL=C sort > "$_spv_actual"

    # Only the recorded lines have to be present; that is what makes this work
    # against a directory holding additional, locally built frameworks.
    _spv_missing=$(LC_ALL=C comm -23 "$_spv_manifest" "$_spv_actual")
    rm -f "$_spv_actual"

    if [ -n "$_spv_missing" ]; then
        echo "provider-verify: provider artifacts changed during staging ($_spv_label):" >&2
        printf '%s\n' "$_spv_missing" | head -20 >&2 || true
        echo "provider-verify: editing anything inside a provider XCFramework destroys its" \
             "SDK-origin signature; stage it byte-for-byte instead" >&2
        return 1
    fi
    spv_note "provider artifacts unchanged ($_spv_label)"
}
