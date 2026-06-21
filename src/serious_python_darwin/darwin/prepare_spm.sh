#!/usr/bin/env bash
set -euo pipefail
#
# prepare_spm.sh <ios|macos>
#
# Host-side equivalent of the podspec `prepare_command` for the Swift Package
# Manager build path (SPM has no pod-install hook). Downloads + extracts the
# Python/dart_bridge dist, syncs the app + site-packages into it, and maps the
# result into the SPM plugin layout. Prints SP_NATIVE_SET (the cache-bust key)
# on stdout; all progress goes to stderr so the caller can capture just the key.
#
# Version coordinates resolve from python_versions.properties (overridable via
# the same env vars the podspec honors), so the caller only passes the platform.
#
platform=${1:?usage: prepare_spm.sh <ios|macos>}
script_dir=$(cd "$(dirname "$0")" && pwd -P)
props="$script_dir/python_versions.properties"

prop() { grep "^$1=" "$props" 2>/dev/null | head -1 | cut -d= -f2-; }

pyver=${SERIOUS_PYTHON_VERSION:-$(prop default_python_version)}
pyfull=${SERIOUS_PYTHON_FULL_VERSION:-$(prop "$pyver.full_version")}
builddate=${SERIOUS_PYTHON_BUILD_DATE:-$(prop python_build_release_date)}
dbver=${DART_BRIDGE_VERSION:-$(prop dart_bridge_version)}
[ -n "$pyfull" ] || { echo "prepare_spm: unknown SERIOUS_PYTHON_VERSION '$pyver'" >&2; exit 1; }

echo "prepare_spm: $platform python=$pyfull build=$builddate dart_bridge=$dbver" >&2
"$script_dir/prepare_$platform.sh" "$pyver" "$pyfull" "$builddate" "$dbver" >&2
"$script_dir/sync_site_packages.sh" >&2
SERIOUS_PYTHON_FULL_VERSION="$pyfull" "$script_dir/stage_spm.sh" "$platform"
