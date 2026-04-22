#import "NativeWebsocketClientPlugin.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>

@class NativeWebsocketClientPlugin;

API_AVAILABLE(ios(13.0))
@interface DXURLSessionNativeWebSocketClient : NSObject <NSURLSessionWebSocketDelegate>

- (instancetype)initWithPlugin:(NativeWebsocketClientPlugin *)plugin;
- (void)connectWithCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)sendTextWithCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)sendBytesWithCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)closeWithCall:(FlutterMethodCall *)call result:(FlutterResult)result;
- (void)disposeSocket;

@end

@interface NativeWebsocketClientPlugin ()

@property(nonatomic, copy, nullable) FlutterEventSink eventSink;
@property(nonatomic, strong, nullable) id webSocketClient;

- (void)emitEvent:(NSDictionary *)event;

@end

API_AVAILABLE(ios(13.0))
@interface DXURLSessionNativeWebSocketClient ()

@property(nonatomic, weak) NativeWebsocketClientPlugin *plugin;
@property(nonatomic, strong, nullable) NSURLSession *session;
@property(nonatomic, strong, nullable) NSURLSessionWebSocketTask *webSocketTask;
@property(nonatomic, assign) BOOL trustAllCertificates;

- (void)receiveNextMessage;
- (void)sendEvent:(NSDictionary *)event;

@end

@implementation NativeWebsocketClientPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    NativeWebsocketClientPlugin *instance = [[NativeWebsocketClientPlugin alloc] init];
    FlutterMethodChannel *methodChannel = [FlutterMethodChannel methodChannelWithName:@"native_websocket_client/methods"
                                                                      binaryMessenger:[registrar messenger]];
    FlutterEventChannel *eventChannel = [FlutterEventChannel eventChannelWithName:@"native_websocket_client/events"
                                                                  binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:methodChannel];
    [eventChannel setStreamHandler:instance];
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    self.eventSink = events;
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"connect"]) {
        [self connect:call result:result];
        return;
    }
    if ([call.method isEqualToString:@"sendText"]) {
        [self sendText:call result:result];
        return;
    }
    if ([call.method isEqualToString:@"sendBytes"]) {
        [self sendBytes:call result:result];
        return;
    }
    if ([call.method isEqualToString:@"close"]) {
        [self close:call result:result];
        return;
    }
    if ([call.method isEqualToString:@"dispose"]) {
        [self disposeSocket];
        result(nil);
        return;
    }
    result(FlutterMethodNotImplemented);
}

- (void)connect:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (@available(iOS 13.0, *)) {
        [self disposeSocket];
        DXURLSessionNativeWebSocketClient *client = [[DXURLSessionNativeWebSocketClient alloc] initWithPlugin:self];
        self.webSocketClient = client;
        [client connectWithCall:call result:result];
        return;
    }
    result([self unsupportedIOSVersionError]);
}

- (void)sendText:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (@available(iOS 13.0, *)) {
        DXURLSessionNativeWebSocketClient *client = (DXURLSessionNativeWebSocketClient *)self.webSocketClient;
        if (![client isKindOfClass:[DXURLSessionNativeWebSocketClient class]]) {
            result([FlutterError errorWithCode:@"not_connected" message:@"WebSocket is not connected." details:nil]);
            return;
        }
        [client sendTextWithCall:call result:result];
        return;
    }
    result([self unsupportedIOSVersionError]);
}

- (void)sendBytes:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (@available(iOS 13.0, *)) {
        DXURLSessionNativeWebSocketClient *client = (DXURLSessionNativeWebSocketClient *)self.webSocketClient;
        if (![client isKindOfClass:[DXURLSessionNativeWebSocketClient class]]) {
            result([FlutterError errorWithCode:@"not_connected" message:@"WebSocket is not connected." details:nil]);
            return;
        }
        [client sendBytesWithCall:call result:result];
        return;
    }
    result([self unsupportedIOSVersionError]);
}

- (void)close:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (@available(iOS 13.0, *)) {
        DXURLSessionNativeWebSocketClient *client = (DXURLSessionNativeWebSocketClient *)self.webSocketClient;
        if (![client isKindOfClass:[DXURLSessionNativeWebSocketClient class]]) {
            result(nil);
            return;
        }
        [client closeWithCall:call result:result];
        return;
    }
    result([self unsupportedIOSVersionError]);
}

- (void)disposeSocket {
    if (@available(iOS 13.0, *)) {
        DXURLSessionNativeWebSocketClient *client = (DXURLSessionNativeWebSocketClient *)self.webSocketClient;
        if ([client isKindOfClass:[DXURLSessionNativeWebSocketClient class]]) {
            [client disposeSocket];
        }
    }
    self.webSocketClient = nil;
}

- (FlutterError *)unsupportedIOSVersionError {
    return [FlutterError errorWithCode:@"unsupported_ios_version"
                               message:@"native_websocket_client requires iOS 13.0 or newer at runtime."
                               details:nil];
}

- (void)emitEvent:(NSDictionary *)event {
    FlutterEventSink sink = self.eventSink;
    if (!sink) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        sink(event);
    });
}

@end

@implementation DXURLSessionNativeWebSocketClient

- (instancetype)initWithPlugin:(NativeWebsocketClientPlugin *)plugin {
    self = [super init];
    if (self) {
        _plugin = plugin;
    }
    return self;
}

- (void)connectWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
    NSString *urlString = [arguments[@"url"] isKindOfClass:[NSString class]] ? arguments[@"url"] : nil;
    NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    if (!url) {
        result([FlutterError errorWithCode:@"invalid_url" message:@"A valid WebSocket URL is required." details:nil]);
        return;
    }

    [self disposeSocket];

    self.trustAllCertificates = [arguments[@"trustAllCertificates"] respondsToSelector:@selector(boolValue)] ? [arguments[@"trustAllCertificates"] boolValue] : NO;
    NSInteger timeoutMillis = [arguments[@"connectTimeoutMillis"] respondsToSelector:@selector(integerValue)] ? [arguments[@"connectTimeoutMillis"] integerValue] : 6000;
    NSDictionary *headerArguments = [arguments[@"headers"] isKindOfClass:[NSDictionary class]] ? arguments[@"headers"] : @{};
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    [headerArguments enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
            headers[(NSString *)key] = (NSString *)value;
        }
    }];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = (NSTimeInterval)timeoutMillis / 1000.0;
    configuration.HTTPAdditionalHeaders = headers;

    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:[NSOperationQueue new]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = (NSTimeInterval)timeoutMillis / 1000.0;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    self.webSocketTask = [self.session webSocketTaskWithRequest:request];
    [self.webSocketTask resume];
    [self receiveNextMessage];
    result(nil);
}

- (void)sendTextWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (!self.webSocketTask) {
        result([FlutterError errorWithCode:@"not_connected" message:@"WebSocket is not connected." details:nil]);
        return;
    }
    NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
    NSString *text = [arguments[@"text"] isKindOfClass:[NSString class]] ? arguments[@"text"] : @"";
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:text];
    [self.webSocketTask sendMessage:message completionHandler:^(NSError *error) {
        if (error) {
            result([FlutterError errorWithCode:@"send_failed" message:error.localizedDescription details:nil]);
            return;
        }
        result(nil);
    }];
}

- (void)sendBytesWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (!self.webSocketTask) {
        result([FlutterError errorWithCode:@"not_connected" message:@"WebSocket is not connected." details:nil]);
        return;
    }
    NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
    FlutterStandardTypedData *bytes = [arguments[@"bytes"] isKindOfClass:[FlutterStandardTypedData class]] ? arguments[@"bytes"] : nil;
    if (!bytes) {
        result([FlutterError errorWithCode:@"invalid_bytes" message:@"A bytes payload is required." details:nil]);
        return;
    }
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithData:bytes.data];
    [self.webSocketTask sendMessage:message completionHandler:^(NSError *error) {
        if (error) {
            result([FlutterError errorWithCode:@"send_failed" message:error.localizedDescription details:nil]);
            return;
        }
        result(nil);
    }];
}

- (void)closeWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
    NSInteger codeValue = [arguments[@"code"] respondsToSelector:@selector(integerValue)] ? [arguments[@"code"] integerValue] : 1000;
    NSString *reason = [arguments[@"reason"] isKindOfClass:[NSString class]] ? arguments[@"reason"] : @"normal closure";
    NSURLSessionWebSocketCloseCode closeCode = NSURLSessionWebSocketCloseCodeNormalClosure;
    if (codeValue >= NSURLSessionWebSocketCloseCodeNormalClosure && codeValue <= NSURLSessionWebSocketCloseCodeTLSHandshakeFailure) {
        closeCode = (NSURLSessionWebSocketCloseCode)codeValue;
    }
    NSData *reasonData = [reason dataUsingEncoding:NSUTF8StringEncoding];
    [self.webSocketTask cancelWithCloseCode:closeCode reason:reasonData];
    result(nil);
}

- (void)disposeSocket {
    NSData *disposeReason = [@"dispose" dataUsingEncoding:NSUTF8StringEncoding];
    [self.webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:disposeReason];
    self.webSocketTask = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
}

- (void)receiveNextMessage {
    __weak typeof(self) weakSelf = self;
    [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (error) {
            [strongSelf sendEvent:@{
                @"type": @"error",
                @"message": error.localizedDescription ?: @"",
                @"code": NSStringFromClass([error class]) ?: @"NSError",
                @"details": [NSNull null]
            }];
            return;
        }
        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            [strongSelf sendEvent:@{ @"type": @"text", @"data": message.string ?: @"" }];
            [strongSelf receiveNextMessage];
            return;
        }
        if (message.type == NSURLSessionWebSocketMessageTypeData) {
            FlutterStandardTypedData *typedData = [FlutterStandardTypedData typedDataWithBytes:message.data ?: [NSData data]];
            [strongSelf sendEvent:@{ @"type": @"bytes", @"data": typedData }];
            [strongSelf receiveNextMessage];
        }
    }];
}

- (void)sendEvent:(NSDictionary *)event {
    [self.plugin emitEvent:event];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    [self sendEvent:@{ @"type": @"open" }];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    NSString *closeReason = [[NSString alloc] initWithData:reason encoding:NSUTF8StringEncoding] ?: @"";
    [self sendEvent:@{
        @"type": @"closed",
        @"code": @(closeCode),
        @"reason": closeReason
    }];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if (self.trustAllCertificates) {
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        if (serverTrust) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
            return;
        }
    }
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

@end
