import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'native_websocket_client.dart';
import 'native_websocket_client_method_channel.dart';

abstract class NativeWebSocketClientPlatform extends PlatformInterface {
  NativeWebSocketClientPlatform() : super(token: _token);

  static final Object _token = Object();

  static NativeWebSocketClientPlatform _instance =
      MethodChannelNativeWebSocketClient();

  static NativeWebSocketClientPlatform get instance => _instance;

  static set instance(NativeWebSocketClientPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<dynamic> receiveEvents() {
    throw UnimplementedError('receiveEvents() has not been implemented.');
  }

  Future<void> connect(Uri uri, NativeWebSocketOptions options) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  Future<void> sendText(String text) {
    throw UnimplementedError('sendText() has not been implemented.');
  }

  Future<void> sendBytes(Uint8List bytes) {
    throw UnimplementedError('sendBytes() has not been implemented.');
  }

  Future<void> close(int code, String reason) {
    throw UnimplementedError('close() has not been implemented.');
  }

  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
