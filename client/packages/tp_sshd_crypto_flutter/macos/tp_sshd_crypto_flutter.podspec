#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tp_sshd_crypto_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tp_sshd_crypto_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Bundles the tp_sshd crypto shim (dartssh2/native) into Flutter app builds.'
  s.description      = <<-DESC
The Flutter build wiring for the tp_sshd_crypto shim. The shim source stays in
the dartssh2 package; this lane only compiles it into the macOS build.
                       DESC
  s.homepage         = 'https://github.com/hhoao/teampilot'
  s.license          = { :type => 'AGPL-3.0', :file => '../../../../LICENSE' }
  s.author           = { 'TeamPilot' => 'hhoao@users.noreply.github.com' }

  # macOS builds run through CocoaPods, not CMake (unlike the linux/ and
  # windows/ lanes of this package, which the Flutter tooling invokes directly).
  # Podspecs have no relative source paths, so Classes/ holds a forwarder C
  # file that relatively imports ../../../dartssh2/native/tp_sshd_crypto.c —
  # the shim is compiled from its one copy in dartssh2, never duplicated here.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  # Current macOS SDKs do not ship LibreSSL headers. Compile against Homebrew
  # OpenSSL 3 and link its static libcrypto, so the app does not need Homebrew
  # at runtime. CI and local builds both need `brew install openssl@3`.
  openssl_prefix = `brew --prefix openssl@3 2>/dev/null`.strip
  openssl_lib = File.join(openssl_prefix, 'lib', 'libcrypto.a')
  unless File.file?(openssl_lib)
    raise "tp_sshd_crypto_flutter: Homebrew OpenSSL 3 is required (brew install openssl@3); missing #{openssl_lib}"
  end

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => "\"#{openssl_prefix}/include\"",
    'OTHER_LDFLAGS' => "\"#{openssl_lib}\""
  }
  s.swift_version = '5.0'
end
