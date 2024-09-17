#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint serious_python_darwin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'serious_python_darwin'
  s.version          = '0.7.1'
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
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'OTHER_LDFLAGS' => '-ObjC -all_load -lc++'
  }
  s.swift_version = '5.0'

  python_version = "3.12"

  dist_ios = "dist_ios"
  dist_macos = "dist_macos"

  prepare_command = <<-CMD

    rm -rf #{dist_ios}
    mkdir -p #{dist_ios}
    dist_ios=$(realpath #{dist_ios})

    ./prepare_ios.sh #{s.version} #{python_version} $dist_ios

    # rm -rf #{dist_macos}
    # mkdir -p #{dist_macos}
    # dist_macos=$(realpath #{dist_macos})

    # ./prepare_macos.sh #{s.version} #{python_version} $dist_macos
    
CMD

puts `#{prepare_command}`

  # iOS frameworks
  ios_xcframeworks_dir = "#{dist_ios}/xcframeworks"
  ios_frameworks = Dir.glob("#{ios_xcframeworks_dir}/*.xcframework").map do |dir|
    ios_xcframeworks_dir + '/' + Pathname.new(dir).basename.to_s
  end

  s.ios.vendored_frameworks = ios_frameworks
  s.ios.resource = ["#{dist_ios}/python-stdlib", "#{dist_ios}/site-packages"]

  macos_xcframeworks_dir = "#{dist_macos}/xcframeworks"
  macos_frameworks = Dir.glob("#{macos_xcframeworks_dir}/*.xcframework").map do |dir|
    macos_xcframeworks_dir + '/' + Pathname.new(dir).basename.to_s
  end

  s.osx.vendored_frameworks = macos_frameworks
  s.osx.resource = ["#{dist_macos}/python-stdlib", "#{dist_macos}/site-packages"]
end
