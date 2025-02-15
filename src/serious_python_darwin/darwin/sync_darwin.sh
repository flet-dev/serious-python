echo "Sync iOS xcframeworks and site-packages"

script_dir=$(dirname $(realpath $0))
dist=$script_dir/dist_macos

# copy site-packages
if [ -n "$SERIOUS_PYTHON_SITE_PACKAGES" ]; then
    mkdir -p $dist/site-packages
    rsync -av --exclude=".*" --delete "$SERIOUS_PYTHON_SITE_PACKAGES/" "$dist/site-packages/"
else
    echo "SERIOUS_PYTHON_SITE_PACKAGES is not set."
fi