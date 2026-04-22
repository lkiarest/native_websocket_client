import Flutter
import Dispatch
import Foundation

public class NativeWebsocketClientPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var webSocketClient: AnyObject?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeWebsocketClientPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "native_websocket_client/methods",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "native_websocket_client/events",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "connect":
      connect(call, result: result)
    case "sendText":
      sendText(call, result: result)
    case "sendBytes":
      sendBytes(call, result: result)
    case "close":
      close(call, result: result)
    case "dispose":
      disposeSocket()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(unsupportedIOSVersionError())
      return
    }

    disposeSocket()

    let client = URLSessionNativeWebSocketClient(eventSinkProvider: { [weak self] in
      self?.eventSink
    })
    webSocketClient = client
    client.connect(call, result: result)
  }

  private func sendText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(unsupportedIOSVersionError())
      return
    }
    guard let client = webSocketClient as? URLSessionNativeWebSocketClient else {
      result(FlutterError(code: "not_connected", message: "WebSocket is not connected.", details: nil))
      return
    }
    client.sendText(call, result: result)
  }

  private func sendBytes(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(unsupportedIOSVersionError())
      return
    }
    guard let client = webSocketClient as? URLSessionNativeWebSocketClient else {
      result(FlutterError(code: "not_connected", message: "WebSocket is not connected.", details: nil))
      return
    }
    client.sendBytes(call, result: result)
  }

  private func close(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *) else {
      result(unsupportedIOSVersionError())
      return
    }
    guard let client = webSocketClient as? URLSessionNativeWebSocketClient else {
      result(nil)
      return
    }
    client.close(call, result: result)
  }

  private func disposeSocket() {
    if #available(iOS 13.0, *), let client = webSocketClient as? URLSessionNativeWebSocketClient {
      client.disposeSocket()
    }
    webSocketClient = nil
  }

  private func unsupportedIOSVersionError() -> FlutterError {
    return FlutterError(
      code: "unsupported_ios_version",
      message: "native_websocket_client requires iOS 13.0 or newer at runtime.",
      details: nil
    )
  }
}

@available(iOS 13.0, *)
private final class URLSessionNativeWebSocketClient: NSObject, URLSessionWebSocketDelegate {
  private let eventSinkProvider: () -> FlutterEventSink?
  private var session: URLSession?
  private var webSocketTask: URLSessionWebSocketTask?
  private var trustAllCertificates = false

  init(eventSinkProvider: @escaping () -> FlutterEventSink?) {
    self.eventSinkProvider = eventSinkProvider
  }

  func connect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let urlString = arguments["url"] as? String,
      let url = URL(string: urlString)
    else {
      result(FlutterError(code: "invalid_url", message: "A valid WebSocket URL is required.", details: nil))
      return
    }

    disposeSocket()

    trustAllCertificates = arguments["trustAllCertificates"] as? Bool ?? false
    let timeoutMillis = arguments["connectTimeoutMillis"] as? Int ?? 6000
    let headers = arguments["headers"] as? [String: String] ?? [:]

    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = TimeInterval(timeoutMillis) / 1000.0
    configuration.httpAdditionalHeaders = headers

    session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
    var request = URLRequest(url: url)
    request.timeoutInterval = TimeInterval(timeoutMillis) / 1000.0
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    webSocketTask = session?.webSocketTask(with: request)
    webSocketTask?.resume()
    receiveNextMessage()
    result(nil)
  }

  func sendText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let task = webSocketTask else {
      result(FlutterError(code: "not_connected", message: "WebSocket is not connected.", details: nil))
      return
    }
    let arguments = call.arguments as? [String: Any]
    let text = arguments?["text"] as? String ?? ""
    task.send(.string(text)) { error in
      if let error = error {
        result(FlutterError(code: "send_failed", message: error.localizedDescription, details: nil))
      } else {
        result(nil)
      }
    }
  }

  func sendBytes(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let task = webSocketTask else {
      result(FlutterError(code: "not_connected", message: "WebSocket is not connected.", details: nil))
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let bytes = arguments["bytes"] as? FlutterStandardTypedData
    else {
      result(FlutterError(code: "invalid_bytes", message: "A bytes payload is required.", details: nil))
      return
    }
    task.send(.data(bytes.data)) { error in
      if let error = error {
        result(FlutterError(code: "send_failed", message: error.localizedDescription, details: nil))
      } else {
        result(nil)
      }
    }
  }

  func close(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let codeValue = arguments?["code"] as? Int ?? 1000
    let reason = arguments?["reason"] as? String ?? "normal closure"
    let code = URLSessionWebSocketTask.CloseCode(rawValue: codeValue) ?? .normalClosure
    webSocketTask?.cancel(with: code, reason: reason.data(using: .utf8))
    result(nil)
  }

  func disposeSocket() {
    webSocketTask?.cancel(with: .normalClosure, reason: "dispose".data(using: .utf8))
    webSocketTask = nil
    session?.invalidateAndCancel()
    session = nil
  }

  private func receiveNextMessage() {
    webSocketTask?.receive { [weak self] result in
      guard let self = self else {
        return
      }
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self.sendEvent(["type": "text", "data": text])
        case .data(let data):
          self.sendEvent(["type": "bytes", "data": FlutterStandardTypedData(bytes: data)])
        @unknown default:
          break
        }
        self.receiveNextMessage()
      case .failure(let error):
        self.sendEvent([
          "type": "error",
          "message": error.localizedDescription,
          "code": String(describing: type(of: error)),
          "details": nil
        ])
      }
    }
  }

  private func sendEvent(_ event: [String: Any?]) {
    let eventSink = eventSinkProvider()
    DispatchQueue.main.async {
      eventSink?(event)
    }
  }

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    sendEvent(["type": "open"])
  }

  public func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    let closeReason = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    sendEvent(["type": "closed", "code": closeCode.rawValue, "reason": closeReason])
  }

  public func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if trustAllCertificates, let serverTrust = challenge.protectionSpace.serverTrust {
      completionHandler(.useCredential, URLCredential(trust: serverTrust))
      return
    }
    completionHandler(.performDefaultHandling, nil)
  }
}
