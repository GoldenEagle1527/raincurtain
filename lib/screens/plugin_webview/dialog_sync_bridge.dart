import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows WebView2 未触发 onJsPrompt/onJsConfirm/onJsAlert 时的同步弹窗桥接。
/// JS 侧通过同步 XHR 阻塞等待，Flutter 侧显示 Material 对话框（独立 UI 线程可响应）。
class DialogSyncBridge {
  DialogSyncBridge._();

  static final DialogSyncBridge instance = DialogSyncBridge._();

  Future<void> Function(String message)? showAlert;
  Future<bool> Function(String message)? showConfirm;
  Future<String?> Function(String message, String defaultValue)? showPrompt;

  void registerHost({
    Future<void> Function(String message)? showAlert,
    Future<bool> Function(String message)? showConfirm,
    Future<String?> Function(String message, String defaultValue)? showPrompt,
  }) {
    this.showAlert = showAlert;
    this.showConfirm = showConfirm;
    this.showPrompt = showPrompt;
  }

  void unregisterHost() {
    showAlert = null;
    showConfirm = null;
    showPrompt = null;
  }

  Future<void> handleHttpRequest(HttpRequest request) async {
    _setCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length < 3 ||
        segments[0] != '__raincurtain_dialog' ||
        segments[1] != 'sync') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final kind = segments[2];
    final message = request.uri.queryParameters['message'] ?? '';
    final defaultValue = request.uri.queryParameters['defaultValue'] ?? '';

    try {
      switch (kind) {
        case 'alert':
          await showAlert?.call(message);
          _writeJson(request, {'ok': true});
        case 'confirm':
          final confirmed = await (showConfirm?.call(message) ?? Future.value(false));
          _writeJson(request, {'value': confirmed});
        case 'prompt':
          final value = await (showPrompt?.call(message, defaultValue) ??
              Future<String?>.value(null));
          _writeJson(request, {'value': value});
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (e, stackTrace) {
      debugPrint('[DialogSyncBridge] handleHttpRequest failed: $e\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  void _writeJson(HttpRequest request, Map<String, dynamic> body) {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  }
}
