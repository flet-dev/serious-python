#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint serious_python_darwin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'serious_python_darwin'
  s.version          = '0.9.3'
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
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-ObjC -all_load -lc++'
  }
  s.swift_version = '5.0'

  python_version = "3.12"

  dist_ios = "dist_ios"
  dist_macos = "dist_macos"

  prepare_command = <<-CMD
    ./symlink_pod.sh
    ./prepare_ios.sh #{python_version}
    ./prepare_macos.sh #{python_version}
    ./sync_site_packages.sh
CMD

puts `#{prepare_command}`

  # iOS frameworks
  s.ios.script_phase = {
    :name => 'Add Python frameworks into iOS app bundle',
    :script => "$PODS_TARGET_SRCROOT/bundle-python-frameworks-ios.sh",
    :execution_position => :before_compile
  }

  s.ios.vendored_frameworks = "dist_ios/xcframeworks/*"
  s.ios.resource_bundles = {
    'python' => [
      "dist_ios/stdlib",
      "dist_ios/site-packages"
    ]
  }

  # macOS frameworks
  s.osx.vendored_frameworks = "dist_macos/xcframeworks/*"
  s.osx.resource_bundles = {
    'python' => [
      "dist_macos/stdlib",
      "dist_macos/site-packages"
    ]
  }
end
