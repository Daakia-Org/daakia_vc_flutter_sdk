Pod::Spec.new do |s|
  s.name             = 'daakia_vc_flutter_sdk'
  s.version          = '4.4.0'
  s.summary          = 'Daakia VC Flutter SDK'
  s.description      = 'A ready-to-use Flutter SDK for seamless audio/video calls, group meetings, and scalable conferencing.'
  s.homepage         = 'https://github.com/daakia/daakia_vc_flutter_sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Daakia' => 'info@daakia.in' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
