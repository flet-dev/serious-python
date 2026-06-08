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

  # CocoaPods silently drops `s.source_files` entries that traverse outside
  # the podspec's directory (`../native/*.c`), so Classes/ contains committed
  # symlinks to the canonical native/ sources. Symlinks (rather than copies)
  # keep native/ as the single source of truth shared with linux/, windows/,
  # android/ CMakeLists builds. The darwin/ pod is only built on Apple
  # platforms where symlinks-in-git work fine.
  #
  # No public headers exposed — Swift accesses PyInit_dart_bridge via
  # dlsym(RTLD_DEFAULT, ...), keeping <Python.h> out of the umbrella modulemap.
  s.source_files = 'Classes/**/*.{swift,c,h}'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.dependency 'serious_python_darwin'

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # First entry: dart_bridge.c does `#include "dart_api/dart_api_dl.h"`.
    # Second entry: dart_bridge.c does `#include <Python.h>` (standard,
    # non-framework form). The Python xcframework's slice is extracted by
    # CocoaPods into PODS_XCFRAMEWORKS_BUILD_DIR/serious_python_darwin/
    # Python.framework, so pointing at its Headers/ subdirectory lets the
    # unprefixed include resolve without changing the .c source.
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../native" "${PODS_XCFRAMEWORKS_BUILD_DIR}/serious_python_darwin/Python.framework/Headers"',
    # Py* symbols are resolved at the final app link against the Python
    # framework provided by serious_python_darwin's vendored xcframework.
    'OTHER_LDFLAGS' => '$(inherited) -undefined dynamic_lookup',
  }
  s.swift_version = '5.0'
end
