Pod::Spec.new do |s|
  s.name             = 'verovio_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Verovio FFI plugin for Flutter.'
  s.homepage         = 'https://www.verovio.org'
  s.license          = { :type => 'LGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'verovio_flutter' => 'noreply@example.com' }
  s.platform         = :ios, '12.0'
  s.source           = { :path => '.' }
  s.source_files        = 'Classes/**/*', '../src/verovio_ffi.h'
  s.public_header_files = 'Classes/**/*.h'
  s.vendored_frameworks = 'Frameworks/VerovioFFI.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
  }
  s.dependency 'Flutter'
  s.swift_version = '5.0'
end
