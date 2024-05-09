version=${1:?}
python_version=${2:?}
dist_ios=${3:?}

# PYTHON_MACOS_DIST_FILE=Python-3.11-macOS-support.b3.tar.gz
# curl -LO https://github.com/beeware/Python-Apple-support/releases/download/3.11-b3/$PYTHON_MACOS_DIST_FILE
# mkdir -p dist_macos
# tar -xzf $PYTHON_MACOS_DIST_FILE -C dist_macos
# rm $PYTHON_MACOS_DIST_FILE

# # compile dist_macos/python-stdlib
# cd dist_macos/python-stdlib
# $ROOT/dist/hostpython3/bin/python -m compileall -b .
# find . \\( -name '*.py' -or -name '*.typed' \\) -type f -delete
# rm -rf __pycache__
# rm -rf **/__pycache__
# cd -

# # compile python311.zip
# PYTHON311_ZIP=$ROOT/dist/root/python3/lib/python311.zip
# unzip $PYTHON311_ZIP -d python311_temp
# rm $PYTHON311_ZIP
# cd python311_temp
# $ROOT/dist/hostpython3/bin/python -m compileall -b .
# find . \\( -name '*.so' -or -name '*.py' -or -name '*.typed' \\) -type f -delete
# zip -r $PYTHON311_ZIP .
# cd -
# rm -rf python311_temp

# # fix import subprocess, asyncio
# cp -R pod_templates/site-packages/* dist/root/python3/lib/python3.11/site-packages

# # zip site-packages
# cd dist/root/python3/lib/python3.11/site-packages
# $ROOT/dist/hostpython3/bin/python -m compileall -b .
# find . \\( -name '*.so' -or -name '*.py' -or -name '*.typed' \\) -type f -delete
# zip -r $ROOT/dist/root/python3/lib/site-packages.zip .
# cd -

# # remove junk
# rm -rf dist/root/python3/lib/python3.11