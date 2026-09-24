# Signature normalization for the Mach-O libraries bundled into a macOS app.
#
# replace_linker_signatures <dir>...
#
# Re-signs ad-hoc every `.so`, `.so.*` and `.dylib` under the given directories
# that has an architecture slice carrying the signature the linker attached
# when it built the file.
#
# A linker signature names the code after the output file, extension included
# (`_ssl.cpython-314-darwin.so`), and codesign never carries metadata over from
# one: re-signing the file derives a fresh identifier from the file name minus
# its extension (`_ssl.cpython-314-darwin`). Xcode's distribution signing
# (Organizer, `xcodebuild -exportArchive`) can write the designated requirement
# from the identifier it read off the existing signature, so a linker-signed
# library ends up with a requirement its own new signature does not satisfy,
# and App Store Connect rejects the upload (error 90238, "does not satisfy its
# designated Requirement"). A regular ad-hoc signature's identifier is carried
# over by re-signing, so the requirement and the signature agree.
#
# Every slice of a universal file is inspected, one file at a time: `codesign
# -d` reports a single slice unless `--architecture` selects one, which slice
# that is depends on the build machine, and given several paths it stops at the
# first one that is not signed. The linker signs arm64 slices and usually
# leaves x86_64 slices unsigned, so the linker signature is often on a slice
# other than the reported one. `codesign --verify` accepts linker signatures,
# so it cannot tell them apart. A file with any linker-signed slice is
# re-signed, all slices at once. Anything else -- already re-signed, unsigned,
# or not Mach-O at all -- is left untouched, so a repeated run only re-checks.
# Ad-hoc signing is deterministic, so re-signing a fresh copy of the same file
# reproduces the same bytes. Paths containing newlines are not supported.
#
# Returns non-zero, after printing the error, when a directory cannot be listed
# or a file cannot be re-signed.
replace_linker_signatures() {
    local dir files bin archs arch err
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        if ! files=$(find "$dir" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \)); then
            echo "replace_linker_signatures: cannot list $dir" >&2
            return 1
        fi
        while IFS= read -r bin; do
            [ -n "$bin" ] || continue
            archs=$(lipo -archs "$bin" 2>/dev/null) || continue
            for arch in $archs; do
                case $(codesign -d --verbose=1 --architecture "$arch" "$bin" 2>&1) in
                    *"CodeDirectory "*linker-signed*) ;;
                    *) continue ;;
                esac
                if ! err=$(codesign --force --sign - "$bin" 2>&1); then
                    echo "replace_linker_signatures: codesign failed for $bin: $err" >&2
                    return 1
                fi
                break
            done
        done <<EOF
$files
EOF
    done
}
