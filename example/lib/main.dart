import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_websocket_client/native_websocket_client.dart';

void main() {
  runApp(const NativeWebSocketExampleApp());
}

class NativeWebSocketExampleApp extends StatelessWidget {
  const NativeWebSocketExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: false, primarySwatch: Colors.indigo),
      home: const WebSocketPage(),
    );
  }
}

class WebSocketPage extends StatefulWidget {
  const WebSocketPage({super.key});

  @override
  State<WebSocketPage> createState() => _WebSocketPageState();
}

class _WebSocketPageState extends State<WebSocketPage> {
  final NativeWebSocketClient _client = NativeWebSocketClient();
  final TextEditingController _urlController = TextEditingController(
    text: 'ws://192.168.43.1:443',
  );
  final TextEditingController _messageController = TextEditingController(
    text: '08ee0000001a07',
  );
  final List<String> _logs = <String>[];
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  NativeWebSocketState _state = NativeWebSocketState.idle;
  bool _trustAllCertificates = false;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(_client.states.listen((state) {
      setState(() {
        _state = state;
        _logs.insert(0, 'state: $state');
      });
    }));
    _subscriptions.add(_client.messages.listen((message) {
      setState(() {
        if (message.isText) {
          _logs.insert(0, 'text: ${message.text}');
        } else {
          _logs.insert(0, 'bytes: ${message.bytes}');
        }
      });
    }));
    _subscriptions.add(_client.errors.listen((error) {
      setState(() {
        _logs.insert(0, 'error: $error');
      });
    }));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _client.dispose();
    _urlController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      await _client.connect(
        Uri.parse(_urlController.text.trim()),
        options: NativeWebSocketOptions(
          connectTimeout: const Duration(seconds: 6),
          trustAllCertificates: _trustAllCertificates,
        ),
      );
      _addLog('open');
    } catch (error) {
      _addLog('connect failed: $error');
    }
  }

  Future<void> _disconnect() async {
    await _client.close();
    _addLog('close requested');
  }

  Future<void> _sendText() async {
    try {
      await _client.sendText(_messageController.text);
      _addLog('sent: ${_messageController.text}');
    } catch (error) {
      _addLog('send failed: $error');
    }
  }

  void _addLog(String log) {
    setState(() {
      _logs.insert(0, log);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConnect = _state != NativeWebSocketState.connecting &&
        _state != NativeWebSocketState.open;
    final canSend = _state == NativeWebSocketState.open;

    return Scaffold(
      appBar: AppBar(title: const Text('Native WebSocket Client')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'WebSocket URL',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Trust all certificates'),
            subtitle: const Text('Use only for local device debugging.'),
            value: _trustAllCertificates,
            onChanged: (value) {
              setState(() {
                _trustAllCertificates = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: ElevatedButton(
                  onPressed: canConnect ? _connect : null,
                  child: const Text('Connect'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _disconnect,
                  child: const Text('Disconnect'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('State: $_state',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Text message',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: canSend ? _sendText : null,
            child: const Text('Send Text'),
          ),
          const SizedBox(height: 20),
          Text('Log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final log in _logs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(log),
            ),
        ],
      ),
    );
  }
}
