import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'native_websocket_client.dart';
import 'native_websocket_client_platform_interface.dart';

class MethodChannelNativeWebSocketClient extends NativeWebSocketClientPlatform {
  @visibleForTesting
  final MethodChannel methodChannel;

  @visibleForTesting
  final EventChannel eventChannel;

  MethodChannelNativeWebSocketClient({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : methodChannel = methodChannel ??
            const MethodChannel('native_websocket_client/methods'),
        eventChannel = eventChannel ??
            const EventChannel('native_websocket_client/events');

  @override
  Stream<dynamic> receiveEvents() => eventChannel.receiveBroadcastStream();

  @override
  Future<void> connect(Uri uri, NativeWebSocketOptions options) {
    return methodChannel.invokeMethod<void>('connect', <String, dynamic>{
      'url': uri.toString(),
      'headers': options.headers,
      'connectTimeoutMillis': options.connectTimeout.inMilliseconds,
      'pingIntervalMillis': options.pingInterval?.inMilliseconds,
      'autoReconnect': options.autoReconnect,
      'trustAllCertificates': options.trustAllCertificates,
    });
  }

  @override
  Future<void> sendText(String text) {
    return methodChannel.invokeMethod<void>('sendText', <String, dynamic>{
      'text': text,
    });
  }

  @override
  Future<void> sendBytes(Uint8List bytes) {
    return methodChannel.invokeMethod<void>('sendBytes', <String, dynamic>{
      'bytes': bytes,
    });
  }

  @override
  Future<void> close(int code, String reason) {
    return methodChannel.invokeMethod<void>('close', <String, dynamic>{
      'code': code,
      'reason': reason,
    });
  }

  @override
  Future<void> dispose() {
    return methodChannel.invokeMethod<void>('dispose');
  }
}
