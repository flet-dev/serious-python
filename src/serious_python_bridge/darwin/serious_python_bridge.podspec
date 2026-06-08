#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint serious_python_bridge.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'serious_python_bridge'
  s.version          = '2.0.0'
  s.summary          = 'Generic in-process Dart ↔ Python byte transport for serious_python.'
  s.description      = <<-DESC
    Pure-FFI Flutter plugin that exposes the dart_bridge C primitives
    (DartBridge_InitDartApiDL, DartBridge_EnqueueMessage) and the matching
    Python module (send_bytes, set_enqueue_handler_func). On Apple platforms
    the bridge is statically linked into the app process and registered with
    CPython via serious_python_darwin's registerPythonExtension hook.
  DESC
  s.homepage         = 'https://flet.dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Appveyor Systems Inc.' => 'hello@flet.dev' }
  s.source           = { :path => '.' }

  # Swift plugin class + C sources from ../native.
  s.source_files = [
    'Classes/**/*.{h,m,swift}',
    '../native/dart_bridge.c',
    '../native/dart_api/dart_api_dl.c',
    '../native/dart_api/*.h',
    '../native/dart_api/internal/*.h',
  ]
  s.public_header_files = 'Classes/**/*.h'
  s.preserve_paths = '../native/dart_api/**/*.h'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.dependency 'serious_python_darwin'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # dart_bridge.c does `#include "dart_api/dart_api_dl.h"`; surface the
    # vendored Dart SDK headers.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../native"',
    # Py* symbols are resolved at the final app link against the Python
    # framework provided by serious_python_darwin's vendored xcframework.
    'OTHER_LDFLAGS' => '$(inherited) -undefined dynamic_lookup',
  }
  s.swift_version = '5.0'
end
