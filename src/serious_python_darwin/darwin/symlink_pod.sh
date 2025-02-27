script_dir=$(cd "$(dirname "$0")" && pwd -P)

# create a symlink to this Pod
if [[ -n "$SERIOUS_PYTHON_SITE_PACKAGES" && -d "$SERIOUS_PYTHON_SITE_PACKAGES" ]]; then
    echo "Creating .pod symlink in SERIOUS_PYTHON_SITE_PACKAGES: $SERIOUS_PYTHON_SITE_PACKAGES"
    rm -f $script_dir $SERIOUS_PYTHON_SITE_PACKAGES/.pod
    ln -s $script_dir $SERIOUS_PYTHON_SITE_PACKAGES/.pod
else
    echo ".pod symlink was not created because SERIOUS_PYTHON_SITE_PACKAGES is not set or directory does not exist."
fi