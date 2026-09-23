# Signature normalization for the Mach-O libraries bundled into a macOS app.
#
# replace_linker_signatures <dir>...
#
# Re-signs ad-hoc every `.so`, `.so.*` and `.dylib` under the given directories
# that carries the signature the linker attached when it built the file.
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
# Files are inspected one at a time, because `codesign -d` given several paths
# stops at the first one that is not signed. Anything that is not
# linker-signed -- already re-signed, unsigned, or not Mach-O at all -- is left
# untouched, so a repeated run only re-checks. Ad-hoc signing is deterministic,
# so re-signing a fresh copy of the same file reproduces the same bytes. Paths
# containing newlines are not supported.
#
# Returns non-zero, after printing the error, when a directory cannot be listed
# or a file cannot be re-signed.
replace_linker_signatures() {
    local dir files bin err
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        if ! files=$(find "$dir" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \)); then
            echo "replace_linker_signatures: cannot list $dir" >&2
            return 1
        fi
        while IFS= read -r bin; do
            [ -n "$bin" ] || continue
            case $(codesign -d --verbose=1 "$bin" 2>&1) in
                *"CodeDirectory "*linker-signed*) ;;
                *) continue ;;
            esac
            if ! err=$(codesign --force --sign - "$bin" 2>&1); then
                echo "replace_linker_signatures: codesign failed for $bin: $err" >&2
                return 1
            fi
        done <<EOF
$files
EOF
    done
}
