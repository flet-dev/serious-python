#!/bin/bash
set -eu

install_root=${1:?}
python_version=${2:?}
abi=${3:?}

script_dir=$(dirname $(realpath $0))

# build short Python version
read python_version_major python_version_minor < <(echo $python_version | sed -E 's/^([0-9]+)\.([0-9]+).*/\1 \2/')
python_version_short=$python_version_major.$python_version_minor

# create build dir
build_dir=build/python-$python_version/$abi
rm -rf $build_dir
mkdir -p $build_dir
build_dir=$(realpath $build_dir)

# create dist dir
dist_dir=dist/python-$python_version/$abi
rm -rf $dist_dir
mkdir -p $dist_dir
dist_dir=$(realpath $dist_dir)

# copy files to build
rsync -av --exclude-from=$script_dir/python-android-distro.exclude $install_root/android/$abi/python-$python_version/* $build_dir

# create libpythonbundle.so
bundle_dir=$build_dir/libpythonbundle
mkdir -p $bundle_dir

# modules with *.so files
mv $build_dir/lib/python$python_version_short/lib-dynload $bundle_dir/modules

# stdlib
# stdlib_zip=$bundle_dir/stdlib.zip
cd $build_dir/lib/python$python_version_short
python -m compileall -b .
find . \( -name '*.so' -or -name '*.py' -or -name '*.typed' \) -type f -delete
rm -rf __pycache__
rm -rf **/__pycache__
# zip -r $stdlib_zip .
cd -
mv $build_dir/lib/python$python_version_short $bundle_dir/stdlib

# compress libpythonbundle
cd $bundle_dir
zip -r ../libpythonbundle.so .
cd -
rm -rf $bundle_dir

# copy *.so from lib
cp $build_dir/lib/*.so $build_dir
rm -rf $build_dir/lib

# final archive
tar -czf $dist_dir/python-$python_version-android-$abi.tar.gz -C $build_dir .