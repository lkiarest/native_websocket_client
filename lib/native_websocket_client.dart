import 'dart:async';
import 'dart:typed_data';

import 'native_websocket_client_platform_interface.dart';

enum NativeWebSocketState {
  idle,
  connecting,
  open,
  closing,
  closed,
  error,
}

class NativeWebSocketOptions {
  const NativeWebSocketOptions({
    this.headers = const <String, String>{},
    this.connectTimeout = const Duration(seconds: 6),
    this.pingInterval,
    this.autoReconnect = false,
    this.trustAllCertificates = false,
  });

  final Map<String, String> headers;
  final Duration connectTimeout;
  final Duration? pingInterval;
  final bool autoReconnect;
  final bool trustAllCertificates;
}

class NativeWebSocketMessage {
  const NativeWebSocketMessage.text(this.text) : bytes = null;
  const NativeWebSocketMessage.bytes(this.bytes) : text = null;

  final String? text;
  final Uint8List? bytes;

  bool get isText => text != null;
  bool get isBytes => bytes != null;
}

class NativeWebSocketException implements Exception {
  NativeWebSocketException(this.message, {this.code, this.details});

  final String message;
  final String? code;
  final Object? details;

  @override
  String toString() {
    if (code == null || code!.isEmpty) {
      return 'NativeWebSocketException: $message';
    }
    return 'NativeWebSocketException($code): $message';
  }
}

class NativeWebSocketClient {
  NativeWebSocketClient({
    NativeWebSocketClientPlatform? platform,
  }) : _platform = platform ?? NativeWebSocketClientPlatform.instance;

  final NativeWebSocketClientPlatform _platform;
  final StreamController<NativeWebSocketState> _states =
      StreamController<NativeWebSocketState>.broadcast();
  final StreamController<NativeWebSocketMessage> _messages =
      StreamController<NativeWebSocketMessage>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  Completer<void>? _connectCompleter;
  Timer? _connectTimer;
  NativeWebSocketState _state = NativeWebSocketState.idle;
  bool _disposed = false;

  Stream<NativeWebSocketState> get states => _states.stream;
  Stream<NativeWebSocketMessage> get messages => _messages.stream;
  Stream<Object> get errors => _errors.stream;

  NativeWebSocketState get state => _state;
  bool get isOpen => _state == NativeWebSocketState.open;

  Future<void> connect(
    Uri uri, {
    NativeWebSocketOptions options = const NativeWebSocketOptions(),
  }) async {
    _ensureUsable();
    if (_state == NativeWebSocketState.connecting ||
        _state == NativeWebSocketState.open ||
        _state == NativeWebSocketState.closing) {
      throw StateError('NativeWebSocketClient already has an active socket.');
    }

    _connectCompleter = Completer<void>();
    _subscribeToEvents();
    _setState(NativeWebSocketState.connecting);

    _connectTimer = Timer(options.connectTimeout, () {
      final completer = _connectCompleter;
      if (completer == null || completer.isCompleted) {
        return;
      }
      _setState(NativeWebSocketState.error);
      _platform.close(1000, 'connect timeout');
      completer.completeError(
        TimeoutException(
          'Native WebSocket open event was not received before timeout.',
          options.connectTimeout,
        ),
      );
    });

    try {
      await _platform.connect(uri, options);
    } catch (error) {
      _finishConnectWithError(error);
    }

    return _connectCompleter!.future;
  }

  Future<void> sendText(String text) {
    if (!isOpen) {
      throw StateError('NativeWebSocketClient is not open.');
    }
    return _platform.sendText(text);
  }

  Future<void> sendBytes(Uint8List bytes) {
    if (!isOpen) {
      throw StateError('NativeWebSocketClient is not open.');
    }
    return _platform.sendBytes(bytes);
  }

  Future<void> close({
    int code = 1000,
    String reason = 'normal closure',
  }) async {
    if (_disposed) {
      return;
    }
    _connectTimer?.cancel();
    if (_state == NativeWebSocketState.closed ||
        _state == NativeWebSocketState.idle) {
      await _platform.close(code, reason);
      _setState(NativeWebSocketState.closed);
      return;
    }
    _setState(NativeWebSocketState.closing);
    await _platform.close(code, reason);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _connectTimer?.cancel();
    await _eventSubscription?.cancel();
    await _platform.dispose();
    _state = NativeWebSocketState.closed;
    await _states.close();
    await _messages.close();
    await _errors.close();
  }

  void _subscribeToEvents() {
    _eventSubscription ??= _platform.receiveEvents().listen(
          _handleEvent,
          onError: _finishConnectWithError,
        );
  }

  void _handleEvent(dynamic event) {
    if (_disposed || event is! Map) {
      return;
    }
    final type = event['type']?.toString();
    switch (type) {
      case 'open':
        _connectTimer?.cancel();
        _setState(NativeWebSocketState.open);
        final completer = _connectCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        break;
      case 'text':
        final data = event['data'];
        if (data is String) {
          _messages.add(NativeWebSocketMessage.text(data));
        }
        break;
      case 'bytes':
        final data = event['data'];
        if (data is Uint8List) {
          _messages.add(NativeWebSocketMessage.bytes(data));
        } else if (data is List) {
          _messages.add(
            NativeWebSocketMessage.bytes(Uint8List.fromList(data.cast<int>())),
          );
        }
        break;
      case 'closing':
        _setState(NativeWebSocketState.closing);
        break;
      case 'closed':
        _connectTimer?.cancel();
        _setState(NativeWebSocketState.closed);
        break;
      case 'error':
        _finishConnectWithError(
          NativeWebSocketException(
            event['message']?.toString() ?? 'Native WebSocket error.',
            code: event['code']?.toString(),
            details: event['details'],
          ),
        );
        break;
    }
  }

  void _finishConnectWithError(Object error) {
    if (_disposed) {
      return;
    }
    _connectTimer?.cancel();
    _setState(NativeWebSocketState.error);
    _errors.add(error);
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void _setState(NativeWebSocketState state) {
    _state = state;
    if (!_states.isClosed) {
      _states.add(state);
    }
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('NativeWebSocketClient has been disposed.');
    }
  }
}
