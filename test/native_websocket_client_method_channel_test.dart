import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_websocket_client/native_websocket_client.dart';
import 'package:native_websocket_client/native_websocket_client_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('native_websocket_client/methods');
  final calls = <MethodCall>[];
  final platform = MethodChannelNativeWebSocketClient(
    methodChannel: channel,
    eventChannel: const EventChannel('native_websocket_client/events'),
  );

  setUp(() {
    calls.clear();
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      calls.add(methodCall);
      return null;
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('connect sends url and options over MethodChannel', () async {
    await platform.connect(
      Uri.parse('wss://192.168.43.1:443/ws'),
      const NativeWebSocketOptions(
        headers: <String, String>{'Authorization': 'token'},
        connectTimeout: Duration(seconds: 6),
        pingInterval: Duration(seconds: 20),
        trustAllCertificates: true,
      ),
    );

    expect(calls.single.method, 'connect');
    expect(calls.single.arguments, <String, dynamic>{
      'url': 'wss://192.168.43.1:443/ws',
      'headers': <String, String>{'Authorization': 'token'},
      'connectTimeoutMillis': 6000,
      'pingIntervalMillis': 20000,
      'autoReconnect': false,
      'trustAllCertificates': true,
    });
  });

  test('send and close methods use documented method names', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    await platform.sendText('hello');
    await platform.sendBytes(bytes);
    await platform.close(1000, 'normal closure');
    await platform.dispose();

    expect(
      calls.map((call) => call.method),
      <String>['sendText', 'sendBytes', 'close', 'dispose'],
    );
    expect(calls[0].arguments, <String, dynamic>{'text': 'hello'});
    expect(calls[1].arguments, <String, dynamic>{'bytes': bytes});
    expect(
      calls[2].arguments,
      <String, dynamic>{'code': 1000, 'reason': 'normal closure'},
    );
  });
}
