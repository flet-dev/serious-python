python_version=${1:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_macos

if [ ! -d "$dist" ]; then
    mkdir -p $dist

    python_macos_dist_file="python-macos-dart-$python_version.tar.gz"
    python_macos_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_macos_dist_file"

    # download macos dist
    curl -LO $python_macos_dist_url
    tar -xzf $python_macos_dist_file -C $dist
    mv $dist/python-stdlib $dist/stdlib
    rm $python_macos_dist_file
fi