# native_websocket_client

Flutter WebSocket plugin that avoids Dart `dart:io` / `dart:_http` WebSocket on mobile platforms.

- Android uses native OkHttp WebSocket.
- iOS uses `URLSessionWebSocketTask`.
- Dart `connect()` completes only after native `onOpen` is delivered.
- Supports text messages, binary messages, state events, connect timeout, close, and dispose.

## Install

Use a path dependency while developing:

```yaml
dependencies:
  native_websocket_client:
    path: ../native_websocket_client
```

Then run:

```bash
flutter pub get
```

## Requirements

- Dart SDK: `>=2.19.3 <3.0.0`
- Flutter SDK: `>=2.5.0`
- Android minSdk: 16
- Android Java: Java 8
- Android Gradle Plugin: compatible with old projects; this plugin does not require AGP 7 `namespace`
- Android WebSocket engine: OkHttp `3.12.13` for old Android compatibility
- iOS minimum deployment target: 13.0 for `URLSessionWebSocketTask`

The Dart API avoids Dart 3 syntax.

## Android Configuration

For local device AP URLs such as `ws://192.168.1.1:443`, the host Android app may need cleartext enabled:

```xml
<application
    android:usesCleartextTraffic="true"
    ...>
</application>
```

Alternatively, configure Android Network Security Config for the target device IP range.

For `wss://` devices using a self-signed certificate, pass `trustAllCertificates: true` in `NativeWebSocketOptions`. This affects only the OkHttpClient instance created for this plugin connection. Do not enable it for internet endpoints.

## iOS Configuration

iOS uses `URLSessionWebSocketTask`, so the deployment target is iOS 13.0 or newer.

For local network device access, the host app may need:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app connects to local devices.</string>
```

Bonjour keys are not required unless the host app discovers devices using Bonjour.

For self-signed `wss://` devices, `trustAllCertificates: true` enables debug-only trust handling for the current connection.

## Usage

```dart
final socket = NativeWebSocketClient();

socket.states.listen(print);
socket.messages.listen((message) {
  if (message.isText) {
    print('text: ${message.text}');
  } else {
    print('bytes: ${message.bytes}');
  }
});
socket.errors.listen(print);

await socket.connect(
  Uri.parse('ws://192.168.43.1:443'),
  options: const NativeWebSocketOptions(
    connectTimeout: Duration(seconds: 6),
  ),
);

await socket.sendText('08ee0000001a07');
await socket.close();
await socket.dispose();
```

## API Notes

- A `NativeWebSocketClient` manages one socket at a time.
- Calling `connect()` while the client is connecting, open, or closing throws `StateError`.
- `connect()` completes only after native open is received.
- If native error arrives during connection, `connect()` completes with `NativeWebSocketException`.
- If no open event arrives before `connectTimeout`, `connect()` throws `TimeoutException` and asks native to close the socket.
- `sendText()` and `sendBytes()` throw `StateError` unless the socket is open.
- `close()` waits only for the native close request to be sent. It does not wait indefinitely for the server close frame.
- `dispose()` cancels Dart subscriptions, closes streams, and disposes the native socket.

## Events

Native sends events through `native_websocket_client/events`:

```json
{ "type": "open" }
{ "type": "text", "data": "..." }
{ "type": "bytes", "data": "Uint8List" }
{ "type": "closing", "code": 1000, "reason": "..." }
{ "type": "closed", "code": 1000, "reason": "..." }
{ "type": "error", "message": "...", "code": "...", "details": "..." }
```

Methods use `native_websocket_client/methods`:

- `connect`
- `sendText`
- `sendBytes`
- `close`
- `dispose`

## Example

Run the bundled example:

```bash
cd example
flutter run
```

The app lets you enter a WebSocket URL, connect or disconnect, send text, toggle debug certificate trust, and inspect state/message logs.

## Manual Android Verification

1. Enable local cleartext in the host app if using `ws://192.168.43.1:443`.
2. Run the example on an Android device connected to the device AP.
3. Test these URLs:
   - `wss://192.168.43.1:443`
   - `wss://192.168.43.1:443/`
   - `wss://192.168.43.1:443/ws`
   - `ws://192.168.43.1:443`
   - `ws://192.168.43.1:443/`
   - `ws://192.168.43.1:443/ws`
4. Confirm the UI logs `state: NativeWebSocketState.open` before sending messages.

## Tests

```bash
flutter test
```
