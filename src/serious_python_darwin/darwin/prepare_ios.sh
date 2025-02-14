python_version=${1:?}

script_dir=$(dirname $(realpath $0))
dist=$script_dir/dist_ios

python_ios_dist_file="python-ios-dart-$python_version.tar.gz"
python_ios_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_ios_dist_file"

# download iOS dist
curl -LO $python_ios_dist_url
tar -xzf $python_ios_dist_file -C $dist
mv $dist/python-stdlib $dist/stdlib
rm $python_ios_dist_file

# convert site-packages to frameworks
$script_dir/sync_ios.sh

# create a symlink to this Pod
if [ -n "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then
    echo "Creating .pod symlink in SERIOUS_PYTHON_SITE_PACKAGES: $SERIOUS_PYTHON_SITE_PACKAGES"
    rm -f $script_dir $SERIOUS_PYTHON_SITE_PACKAGES/.pod
    ln -s $script_dir $SERIOUS_PYTHON_SITE_PACKAGES/.pod
else
    echo ".pod symlink was not created because SERIOUS_PYTHON_SITE_PACKAGES is not set."
fi