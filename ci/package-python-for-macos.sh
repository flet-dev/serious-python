#!/bin/bash
set -eu

python_apple_support_root=${1:?}
python_version=${2:?}

script_dir=$(dirname $(realpath $0))

# build short Python version
read python_version_major python_version_minor < <(echo $python_version | sed -E 's/^([0-9]+)\.([0-9]+).*/\1 \2/')
python_version_short=$python_version_major.$python_version_minor

# create build directory
build_dir=build/python-$python_version
rm -rf $build_dir
mkdir -p $build_dir
build_dir=$(realpath $build_dir)

# create dist directory
dist_dir=dist/python-$python_version
rm -rf $dist_dir
mkdir -p $dist_dir
dist_dir=$(realpath $dist_dir)

frameworks_dir=$build_dir/xcframeworks
stdlib_dir=$build_dir/python-stdlib
mkdir -p $frameworks_dir
mkdir -p $stdlib_dir

# copy Python.xcframework
rsync -av $python_apple_support_root/support/$python_version_short/macOS/Python.xcframework $frameworks_dir
cp $script_dir/module.modulemap $frameworks_dir/Python.xcframework/macos-arm64_x86_64/Headers

# copy stdlibs
rsync -av --exclude-from=$script_dir/python-darwin-distro.exclude $python_apple_support_root/install/macOS/macosx/python-*/lib/python$python_version_short/* $stdlib_dir

# compile stdlib
cd $stdlib_dir
python -m compileall -b .
find . \( -name '*.py' -or -name '*.typed' \) -type f -delete
rm -rf __pycache__
rm -rf **/__pycache__
cd -

# final archive
tar -czf $dist_dir/python-$python_version-macos.tar.gz -C $build_dir .