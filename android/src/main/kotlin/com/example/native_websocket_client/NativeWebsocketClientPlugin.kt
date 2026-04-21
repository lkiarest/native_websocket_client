package com.example.native_websocket_client

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class NativeWebsocketClientPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private val mainHandler = Handler(Looper.getMainLooper())

  private var eventSink: EventChannel.EventSink? = null
  private var client: OkHttpClient? = null
  private var webSocket: WebSocket? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(binding.binaryMessenger, "native_websocket_client/methods")
    eventChannel = EventChannel(binding.binaryMessenger, "native_websocket_client/events")
    methodChannel.setMethodCallHandler(this)
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    disposeSocket()
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    eventSink = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "connect" -> connect(call, result)
      "sendText" -> sendText(call, result)
      "sendBytes" -> sendBytes(call, result)
      "close" -> close(call, result)
      "dispose" -> {
        disposeSocket()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun connect(call: MethodCall, result: MethodChannel.Result) {
    val url = call.argument<String>("url")
    if (url == null || url.isEmpty()) {
      result.error("invalid_url", "A non-empty WebSocket URL is required.", null)
      return
    }

    disposeSocket()

    val connectTimeoutMillis = call.argument<Int>("connectTimeoutMillis") ?: 6000
    val pingIntervalMillis = call.argument<Int>("pingIntervalMillis")
    val trustAllCertificates = call.argument<Boolean>("trustAllCertificates") ?: false
    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()

    val builder = OkHttpClient.Builder()
      .connectTimeout(connectTimeoutMillis.toLong(), TimeUnit.MILLISECONDS)
      .readTimeout(0, TimeUnit.MILLISECONDS)

    if (pingIntervalMillis != null && pingIntervalMillis > 0) {
      builder.pingInterval(pingIntervalMillis.toLong(), TimeUnit.MILLISECONDS)
    }
    if (trustAllCertificates) {
      applyTrustAllCertificates(builder)
    }

    val requestBuilder = Request.Builder().url(url)
    for ((key, value) in headers) {
      requestBuilder.addHeader(key, value)
    }

    client = builder.build()
    webSocket = client!!.newWebSocket(requestBuilder.build(), NativeListener())
    result.success(null)
  }

  private fun sendText(call: MethodCall, result: MethodChannel.Result) {
    val text = call.argument<String>("text")
    val socket = webSocket
    if (socket == null) {
      result.error("not_connected", "WebSocket is not connected.", null)
      return
    }
    val sent = socket.send(text ?: "")
    if (sent) {
      result.success(null)
    } else {
      result.error("send_failed", "OkHttp WebSocket rejected text send.", null)
    }
  }

  private fun sendBytes(call: MethodCall, result: MethodChannel.Result) {
    val bytes = call.argument<ByteArray>("bytes")
    val socket = webSocket
    if (socket == null) {
      result.error("not_connected", "WebSocket is not connected.", null)
      return
    }
    if (bytes == null) {
      result.error("invalid_bytes", "A bytes payload is required.", null)
      return
    }
    val sent = socket.send(ByteString.of(*bytes))
    if (sent) {
      result.success(null)
    } else {
      result.error("send_failed", "OkHttp WebSocket rejected bytes send.", null)
    }
  }

  private fun close(call: MethodCall, result: MethodChannel.Result) {
    val code = call.argument<Int>("code") ?: 1000
    val reason = call.argument<String>("reason") ?: "normal closure"
    val socket = webSocket
    if (socket != null) {
      socket.close(code, reason)
    }
    result.success(null)
  }

  private fun disposeSocket() {
    val socket = webSocket
    webSocket = null
    socket?.close(1000, "dispose")
    client?.dispatcher()?.executorService()?.shutdown()
    client = null
  }

  private fun sendEvent(event: Map<String, Any?>) {
    mainHandler.post {
      eventSink?.success(event)
    }
  }

  private fun applyTrustAllCertificates(builder: OkHttpClient.Builder) {
    val trustManager = object : X509TrustManager {
      override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
      override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
      override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
    }
    val sslContext = SSLContext.getInstance("TLS")
    sslContext.init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
    builder.sslSocketFactory(sslContext.socketFactory, trustManager)
    builder.hostnameVerifier { _, _ -> true }
  }

  private inner class NativeListener : WebSocketListener() {
    override fun onOpen(webSocket: WebSocket, response: Response) {
      sendEvent(mapOf("type" to "open"))
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
      sendEvent(mapOf("type" to "text", "data" to text))
    }

    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
      sendEvent(mapOf("type" to "bytes", "data" to bytes.toByteArray()))
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
      sendEvent(mapOf("type" to "closing", "code" to code, "reason" to reason))
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
      sendEvent(mapOf("type" to "closed", "code" to code, "reason" to reason))
    }

    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
      sendEvent(
        mapOf(
          "type" to "error",
          "message" to (t.message ?: t.javaClass.simpleName),
          "code" to t.javaClass.simpleName,
          "details" to response?.code()
        )
      )
    }
  }
}
