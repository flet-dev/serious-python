python_version=${1:?}
dist=${2:?}

python_ios_dist_file="python-ios-dart-$python_version.tar.gz"
python_ios_dist_url="https://github.com/flet-dev/python-build/releases/download/v$python_version/$python_ios_dist_file"

# download iOS dist
curl -LO $python_ios_dist_url
tar -xzf $python_ios_dist_file -C $dist
rm $python_ios_dist_file

mkdir $dist/site-packages

echo "$SERIOUS_PYTHON_SITE_PACKAGES" > $dist/site-packages/readme.txt