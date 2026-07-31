#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint serious_python_darwin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'serious_python_darwin'
  s.version          = '4.5.1'
  s.summary          = 'A cross-platform plugin for adding embedded Python runtime to your Flutter apps.'
  s.description      = <<-DESC
  A cross-platform plugin for adding embedded Python runtime to your Flutter apps.
                       DESC
  s.homepage         = 'https://flet.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Appveyor Systems Inc.' => 'hello@flet.dev' }
  s.source           = { :path => '.' }
  # This pod's own Swift code links as a static framework. The vendored
  # xcframeworks below (Python, dart_bridge) are dynamic frameworks — they are
  # embedded and signed into the host app, and their symbols stay exported so
  # the dlsym lookups Dart and Python perform at runtime resolve.
  s.static_framework = true
  s.source_files = ['serious_python_darwin/Sources/serious_python_darwin/**/*.swift']
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'

  # Flutter.framework does not contain a i386 slice.
  # `-all_load` is no longer needed: it existed to retain the static
  # libdart_bridge.a against -dead_strip, and dart_bridge now ships as a dynamic
  # framework whose symbols are exported from its own loaded image.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-ObjC -lc++'
  }
  s.swift_version = '5.0'

  # Python runtime versions come from the generated python_versions.properties
  # (a snapshot of python-build's manifest.json — see serious_python's
  # `gen_version_tables`). SERIOUS_PYTHON_VERSION selects the version; the rest
  # derive from the table. The per-field env vars are escape hatches.
  pv = {}
  File.foreach(File.join(__dir__, 'python_versions.properties')) do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')
    k, v = line.split('=', 2)
    pv[k] = v
  end
  python_version = ENV['SERIOUS_PYTHON_VERSION'] || pv['default_python_version']
  python_full_version = ENV['SERIOUS_PYTHON_FULL_VERSION'] || pv["#{python_version}.full_version"]
  python_build_date = ENV['SERIOUS_PYTHON_BUILD_DATE'] || pv['python_build_release_date']
  dart_bridge_version = ENV['DART_BRIDGE_VERSION'] || pv['dart_bridge_version']
  raise "serious_python: unknown SERIOUS_PYTHON_VERSION '#{python_version}'" if python_full_version.nil?

  dist_ios = "dist_ios"
  dist_macos = "dist_macos"

  prepare_command = <<-CMD
    ./symlink_pod.sh
    ./prepare_ios.sh #{python_version} #{python_full_version} #{python_build_date} #{dart_bridge_version}
    ./prepare_macos.sh #{python_version} #{python_full_version} #{python_build_date} #{dart_bridge_version}
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
      "dist_ios/site-packages",
      "dist_ios/app"
    ]
  }

  # macOS frameworks
  s.osx.vendored_frameworks = "dist_macos/xcframeworks/*"
  s.osx.resource_bundles = {
    'python' => [
      "dist_macos/stdlib",
      "dist_macos/site-packages",
      "dist_macos/app"
    ]
  }
end
