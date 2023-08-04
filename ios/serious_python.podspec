#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint serious_python.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'serious_python'
  s.version          = '0.2.3'
  s.summary          = 'A cross-platform plugin for adding embedded Python runtime to your Flutter apps.'
  s.description      = <<-DESC
  A cross-platform plugin for adding embedded Python runtime to your Flutter apps.
                       DESC
  s.homepage         = 'https://flet.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Appveyor Systems Inc.' => 'hello@flet.dev' }
  s.source           = { :path => '.' }
  #s.static_framework = true
  s.source_files = ['Classes/**/*']
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'OTHER_LDFLAGS' => '-ObjC -all_load -lc++'
  }
  s.swift_version = '5.0'

  python_framework = 'dist/frameworks/Python.xcframework'
  s.prepare_command = <<-CMD
    if [ -d "dist" ]; then
      rm -rf dist
    fi
    if [ -n "$SERIOUS_PYTHON_DIST" ]; then
      ln -s "$SERIOUS_PYTHON_DIST" dist
    else
      PYTHON_DIST_FILE=python-ios-dist-v#{s.version}.tar.gz
      curl -LO https://github.com/flet-dev/serious-python/releases/download/v#{s.version}/$PYTHON_DIST_FILE
      tar -xzf $PYTHON_DIST_FILE
      rm $PYTHON_DIST_FILE
    fi
    ROOT=`pwd`
    rm -rf #{python_framework}
    mkdir -p #{python_framework}
    cp -R pod_templates/Python.xcframework/* #{python_framework}
    cp dist/lib/libpython3.a #{python_framework}/ios-arm64
    cp dist/lib/libpython3.a #{python_framework}/ios-arm64_x86_64-simulator
    cp -R dist/root/python3/include/python3.10/* #{python_framework}/ios-arm64/Headers
    cp -R dist/root/python3/include/python3.10/* #{python_framework}/ios-arm64_x86_64-simulator/Headers

    # compile python310.zip
    PYTHON310_ZIP=$ROOT/dist/root/python3/lib/python310.zip
    unzip $PYTHON310_ZIP -d python310_temp
    rm $PYTHON310_ZIP
    pushd python310_temp
    $ROOT/dist/hostpython3/bin/python -m compileall -b .
    find . \\( -name '*.so' -or -name '*.py' -or -name '*.typed' \\) -type f -delete
    zip -r $PYTHON310_ZIP .
    popd
    rm -rf python310_temp

    # fix import subprocess, asyncio
    cp -R pod_templates/site-packages/* dist/root/python3/lib/python3.10/site-packages

    # zip site-packages
    pushd dist/root/python3/lib/python3.10/site-packages
    $ROOT/dist/hostpython3/bin/python -m compileall -b .
    find . \\( -name '*.so' -or -name '*.py' -or -name '*.typed' \\) -type f -delete
    zip -r $ROOT/dist/root/python3/lib/site-packages.zip .
    popd
  
    # remove junk
    rm -rf dist/root/python3/lib/python3.10
CMD

  s.libraries = 'z', 'bz2', 'c++', 'sqlite3'
  s.vendored_libraries = 'dist/lib/*.a'
  s.vendored_frameworks = python_framework
  s.resource = ['dist/root/python3/lib']
end
