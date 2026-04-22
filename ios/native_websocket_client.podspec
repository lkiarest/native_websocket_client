#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint native_websocket_client.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'native_websocket_client'
  s.version          = '0.0.1'
  s.summary          = 'Native WebSocket client for Flutter.'
  s.description      = <<-DESC
Native WebSocket client for Flutter using OkHttp on Android and URLSessionWebSocketTask on iOS.
                       DESC
  s.homepage         = 'https://example.com/native_websocket_client'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'native_websocket_client' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  
  # 声明 Swift 代码所需的框架依赖
  # Foundation - URLSession, URLRequest, URLAuthenticationChallenge, URLCredential, Data, String 等
  s.frameworks = ['Foundation']

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
