python_version=${1:?}

script_dir=$(cd "$(dirname "$0")" && pwd -P)
dist=$script_dir/dist_ios

if [ ! -d "$dist" ]; then
    mkdir -p $dist

    python_ios_dist_file="python-ios-dart-$python_version.tar.gz"
    python_ios_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_ios_dist_file"

    # download iOS dist
    curl -LO $python_ios_dist_url
    tar -xzf $python_ios_dist_file -C $dist
    mv $dist/python-stdlib $dist/stdlib
    rm $python_ios_dist_file
fi