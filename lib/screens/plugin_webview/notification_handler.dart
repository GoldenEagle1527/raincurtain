import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 全局单例通知插件（避免重复初始化）
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 通知相关的 JS polyfill 和 Handler 注册
mixin NotificationMixin {
  int _notifId = 0;

  /// 注入 JS：覆盖 window.Notification，桥接到 Flutter
  static const String polyfillJS = r"""
(function() {
  if (window.__raincurtainNotifPatched) return;
  window.__raincurtainNotifPatched = true;

  // 模拟 Notification 权限状态
  let _permission = 'default';

  function FakeNotification(title, options) {
    const body = (options && options.body) ? options.body : '';
    window.flutter_inappwebview.callHandler('raincurtain_notify', {
      action: 'show',
      title: title,
      body: body,
    });
  }

  FakeNotification.permission = _permission;

  FakeNotification.requestPermission = function() {
    return window.flutter_inappwebview.callHandler('raincurtain_notify', {
      action: 'requestPermission',
    }).then(function(result) {
      _permission = result || 'granted';
      FakeNotification.permission = _permission;
      return _permission;
    });
  };

  window.Notification = FakeNotification;
})();
""";

  /// 初始化本地通知插件
  Future<void> initNotifications() async {
    // Windows 平台使用原生 Web Notification API，无需 Flutter 侧初始化
    if (Platform.isWindows) {
      return;
    }

    // 仅在 Android 平台初始化
    if (Platform.isAndroid) {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // 处理通知点击事件
          debugPrint('通知被点击: ${response.payload}');
        },
      );

      // Android 13+ 申请通知权限
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  /// 发出一条系统通知（仅 Android）
  Future<void> _showNotification(String title, String body) async {
    // Windows 平台不应该调用此方法，直接使用原生通知
    if (!Platform.isAndroid) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'raincurtain_webview_channel',
      'WebView 通知',
      channelDescription: '来自插件 WebView 的通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(_notifId++, title, body, details);
  }

  /// 注册通知 Handler
  void registerNotificationHandlers(InAppWebViewController controller) {
    // 仅在非 Windows 平台注册通知 Handler
    // Windows 平台使用原生 Web Notification API
    if (!Platform.isWindows) {
      controller.addJavaScriptHandler(
        handlerName: 'raincurtain_notify',
        callback: (args) async {
          if (args.isEmpty) return 'denied';
          final data = args[0] as Map<dynamic, dynamic>;
          final action = data['action'] as String? ?? '';
          if (action == 'requestPermission') {
            // 直接返回 granted，无需再弹框（已在启动时申请过）
            return 'granted';
          } else if (action == 'show') {
            final title = (data['title'] as String?) ?? '通知';
            final body = (data['body'] as String?) ?? '';
            await _showNotification(title, body);
          }
          return null;
        },
      );
    }
  }
}
