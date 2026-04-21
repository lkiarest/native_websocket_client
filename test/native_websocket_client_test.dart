import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_websocket_client/native_websocket_client.dart';
import 'package:native_websocket_client/native_websocket_client_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeNativeWebSocketPlatform extends NativeWebSocketClientPlatform
    with MockPlatformInterfaceMixin {
  final StreamController<Map<dynamic, dynamic>> _events =
      StreamController<Map<dynamic, dynamic>>.broadcast();

  final List<String> calls = <String>[];
  Uri? connectedUri;
  NativeWebSocketOptions? connectedOptions;
  String? sentText;
  Uint8List? sentBytes;
  int? closeCode;
  String? closeReason;

  Stream<Map<dynamic, dynamic>> get events => _events.stream;

  @override
  Stream<dynamic> receiveEvents() => events;

  @override
  Future<void> connect(Uri uri, NativeWebSocketOptions options) async {
    calls.add('connect');
    connectedUri = uri;
    connectedOptions = options;
  }

  @override
  Future<void> sendText(String text) async {
    calls.add('sendText');
    sentText = text;
  }

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    calls.add('sendBytes');
    sentBytes = bytes;
  }

  @override
  Future<void> close(int code, String reason) async {
    calls.add('close');
    closeCode = code;
    closeReason = reason;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }

  void emit(Map<dynamic, dynamic> event) {
    _events.add(event);
  }

  Future<void> closeEvents() => _events.close();
}

void main() {
  late FakeNativeWebSocketPlatform platform;
  late NativeWebSocketClient client;

  setUp(() {
    platform = FakeNativeWebSocketPlatform();
    NativeWebSocketClientPlatform.instance = platform;
    client = NativeWebSocketClient();
  });

  tearDown(() async {
    await client.dispose();
    await platform.closeEvents();
  });

  test('connect completes only after native open and state becomes open',
      () async {
    final states = <NativeWebSocketState>[];
    final subscription = client.states.listen(states.add);

    final connectFuture = client.connect(Uri.parse('ws://192.168.43.1:443'));
    await pumpEventQueue();

    expect(platform.calls, <String>['connect']);
    expect(client.state, NativeWebSocketState.connecting);
    expect(states, contains(NativeWebSocketState.connecting));

    platform.emit(<String, dynamic>{'type': 'open'});
    await connectFuture;

    expect(client.state, NativeWebSocketState.open);
    expect(client.isOpen, isTrue);
    expect(states, contains(NativeWebSocketState.open));

    await subscription.cancel();
  });

  test('connect timeout closes native socket and throws TimeoutException',
      () async {
    final connectFuture = client.connect(
      Uri.parse('ws://192.168.43.1:443'),
      options: const NativeWebSocketOptions(
        connectTimeout: Duration(milliseconds: 1),
      ),
    );

    await expectLater(connectFuture, throwsA(isA<TimeoutException>()));
    expect(platform.calls, <String>['connect', 'close']);
    expect(client.state, NativeWebSocketState.error);
  });

  test('native error during connect completes connect with exception',
      () async {
    final connectFuture = client.connect(Uri.parse('ws://192.168.43.1:443'));
    await pumpEventQueue();

    platform.emit(<String, dynamic>{
      'type': 'error',
      'message': 'TLS handshake failed',
      'code': 'SSL',
    });

    await expectLater(
      connectFuture,
      throwsA(
        isA<NativeWebSocketException>()
            .having((e) => e.message, 'message', 'TLS handshake failed')
            .having((e) => e.code, 'code', 'SSL'),
      ),
    );
    expect(client.state, NativeWebSocketState.error);
  });

  test('text and bytes messages are forwarded to messages stream', () async {
    final messages = <NativeWebSocketMessage>[];
    final subscription = client.messages.listen(messages.add);

    final connectFuture = client.connect(Uri.parse('ws://192.168.43.1:443'));
    platform.emit(<String, dynamic>{'type': 'open'});
    await connectFuture;

    platform.emit(<String, dynamic>{'type': 'text', 'data': 'hello'});
    platform.emit(<String, dynamic>{
      'type': 'bytes',
      'data': Uint8List.fromList(<int>[1, 2, 3]),
    });
    await pumpEventQueue();

    expect(messages[0].isText, isTrue);
    expect(messages[0].text, 'hello');
    expect(messages[1].isBytes, isTrue);
    expect(messages[1].bytes, <int>[1, 2, 3]);

    await subscription.cancel();
  });

  test('send text and bytes require an open socket', () async {
    expect(() => client.sendText('before'), throwsStateError);
    expect(
      () => client.sendBytes(Uint8List.fromList(<int>[1])),
      throwsStateError,
    );

    final connectFuture = client.connect(Uri.parse('ws://192.168.43.1:443'));
    platform.emit(<String, dynamic>{'type': 'open'});
    await connectFuture;

    await client.sendText('08ee0000001a07');
    final bytes = Uint8List.fromList(<int>[8, 238]);
    await client.sendBytes(bytes);

    expect(platform.sentText, '08ee0000001a07');
    expect(platform.sentBytes, bytes);
  });

  test('close emits closing and delegates close request', () async {
    final states = <NativeWebSocketState>[];
    final subscription = client.states.listen(states.add);
    final connectFuture = client.connect(Uri.parse('ws://192.168.43.1:443'));
    platform.emit(<String, dynamic>{'type': 'open'});
    await connectFuture;

    await client.close(code: 1001, reason: 'going away');

    expect(platform.closeCode, 1001);
    expect(platform.closeReason, 'going away');
    expect(client.state, NativeWebSocketState.closing);
    expect(states, contains(NativeWebSocketState.closing));

    platform.emit(<String, dynamic>{
      'type': 'closed',
      'code': 1001,
      'reason': 'going away',
    });
    await pumpEventQueue();
    expect(client.state, NativeWebSocketState.closed);

    await subscription.cancel();
  });

  test('dispose cleans platform resources and closes streams', () async {
    await client.dispose();

    expect(platform.calls, <String>['dispose']);
    expect(client.state, NativeWebSocketState.closed);
  });
}
