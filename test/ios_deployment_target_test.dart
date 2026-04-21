import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS pod supports host apps with deployment target 12', () {
    final podspec =
        File('ios/native_websocket_client.podspec').readAsStringSync();
    final swift = File('ios/Classes/NativeWebsocketClientPlugin.swift')
        .readAsStringSync();

    expect(podspec, contains("s.platform = :ios, '12.0'"));
    expect(swift, contains('@available(iOS 13.0, *)'));
    expect(swift, contains('unsupported_ios_version'));
  });
}
