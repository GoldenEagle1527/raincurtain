import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/plugin_data_manager.dart';

/// 插件 WebView 视图
/// 加载并显示插件的 Web 内容
class PluginWebView extends StatefulWidget {
  final LocalPlugin plugin;

  const PluginWebView({super.key, required this.plugin});

  @override
  State<PluginWebView> createState() => PluginWebViewState();
}

/// 全局单例通知插件（避免重复初始化）
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

class PluginWebViewState extends State<PluginWebView> {
  InAppWebViewController? webViewController;
  double progress = 0;
  bool hasError = false;
  String? errorMessage;
  int _notifId = 0;
  ThemeData? _currentTheme;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newTheme = Theme.of(context);
    if (_currentTheme != null && _currentTheme != newTheme && webViewController != null) {
      // 主题发生变化，且 webview 已经加载
      webViewController?.evaluateJavascript(source: _generateThemeJS(newTheme));
    }
    _currentTheme = newTheme;
  }

  String _toHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  String _generateThemeJS(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final successColor = isLight ? '#2E7D32' : '#81C784';
    final elevation = isLight
        ? '0 1px 2px rgba(0,0,0,.3), 0 1px 3px 1px rgba(0,0,0,.15)'
        : '0 1px 2px rgba(0,0,0,.6), 0 1px 3px 1px rgba(0,0,0,.4)';

    return '''
(function() {
  // 注入全局字体和 Material Icons 字体 (使用本地字体文件)
  function _injectFontStyles() {
    var fontStyleEl = document.getElementById('raincurtain-material-icons-fonts');
    if (!fontStyleEl) {
      fontStyleEl = document.createElement('style');
      fontStyleEl.id = 'raincurtain-material-icons-fonts';
      fontStyleEl.textContent = `
        @font-face {
          font-family: 'NotoSerifSC';
          font-style: normal;
          font-weight: 200 900;
          src: url('http://localhost:8080/__raincurtain_fonts__/NotoSerifSC-VariableFont_wght.ttf') format('truetype');
        }
        
        @font-face {
          font-family: 'Material Icons';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:8080/__raincurtain_fonts__/MaterialIcons-Regular.ttf') format('truetype');
        }
        
        @font-face {
          font-family: 'Material Icons Outlined';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:8080/__raincurtain_fonts__/MaterialIconsOutlined-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Rounded';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:8080/__raincurtain_fonts__/MaterialIconsRounded-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Sharp';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:8080/__raincurtain_fonts__/MaterialIconsSharp-Regular.otf') format('opentype');
        }
        
        @font-face {
          font-family: 'Material Icons Two Tone';
          font-style: normal;
          font-weight: 400;
          src: url('http://localhost:8080/__raincurtain_fonts__/MaterialIconsTwoTone-Regular.otf') format('opentype');
        }
      `;
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.appendChild(fontStyleEl);
      }
    }
  }
  
  // 立即尝试注入字体样式
  var _fontParent = document.head || document.documentElement;
  if (_fontParent) {
    _injectFontStyles();
  } else {
    // DOM 未就绪，监听直到可用
    var _fontObs = new MutationObserver(function() {
      if (document.head || document.documentElement) {
        _fontObs.disconnect();
        _injectFontStyles();
      }
    });
    _fontObs.observe(document, { childList: true, subtree: true });
  }
  
  var cssText = `
    :root {
      --md-primary: ${_toHex(colorScheme.primary)};
      --md-on-primary: ${_toHex(colorScheme.onPrimary)};
      --md-primary-container: ${_toHex(colorScheme.primaryContainer)};
      --md-on-primary-container: ${_toHex(colorScheme.onPrimaryContainer)};
      --md-surface: ${_toHex(colorScheme.surface)};
      --md-surface-container: ${_toHex(colorScheme.surfaceContainer)};
      --md-surface-container-high: ${_toHex(colorScheme.surfaceContainerHigh)};
      --md-on-surface: ${_toHex(colorScheme.onSurface)};
      --md-on-surface-variant: ${_toHex(colorScheme.onSurfaceVariant)};
      --md-outline-variant: ${_toHex(colorScheme.outlineVariant)};
      --md-error: ${_toHex(colorScheme.error)};
      --md-success: $successColor;

      --md-radius-button: 20px;
      --md-radius-card: 12px;
      --md-elevation-1: $elevation;
      --md-font: 'NotoSerifSC', 'Noto Serif SC', serif, system-ui;
      
      /* Material Icons 字体族 */
      --md-font-material-icons: 'Material Icons';
      --md-font-material-icons-outlined: 'Material Icons Outlined';
      --md-font-material-icons-rounded: 'Material Icons Rounded';
      --md-font-material-icons-sharp: 'Material Icons Sharp';
      --md-font-material-icons-two-tone: 'Material Icons Two Tone';
      
      /* 滚动条样式变量 */
      --md-scrollbar-width: 8px;
      --md-scrollbar-height: 8px;
      --md-scrollbar-track-bg: ${_toHex(colorScheme.surfaceContainer)};
      --md-scrollbar-track-radius: 4px;
      --md-scrollbar-thumb-bg: ${_toHex(colorScheme.outlineVariant)};
      --md-scrollbar-thumb-hover-bg: ${_toHex(colorScheme.onSurfaceVariant)};
      --md-scrollbar-thumb-radius: 4px;
    }
    html, body {
      margin: 0; padding: 0;
      box-sizing: border-box;
      font-family: var(--md-font);
      background-color: var(--md-surface);
      color: var(--md-on-surface);
    }
    *, *::before, *::after {
      box-sizing: inherit;
    }
    
    /* Material Icons 基础样式类 */
    .material-icons {
      font-family: var(--md-font-material-icons);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-outlined {
      font-family: var(--md-font-material-icons-outlined);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-rounded {
      font-family: var(--md-font-material-icons-rounded);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-sharp {
      font-family: var(--md-font-material-icons-sharp);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    .material-icons-two-tone {
      font-family: var(--md-font-material-icons-two-tone);
      font-weight: normal;
      font-style: normal;
      font-size: 24px;
      line-height: 1;
      letter-spacing: normal;
      text-transform: none;
      display: inline-block;
      white-space: nowrap;
      word-wrap: normal;
      direction: ltr;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
      -moz-osx-font-smoothing: grayscale;
      font-feature-settings: 'liga';
    }
    
    /* 滚动条样式 - Webkit 浏览器 */
    ::-webkit-scrollbar {
      width: var(--md-scrollbar-width);
      height: var(--md-scrollbar-height);
    }
    ::-webkit-scrollbar-track {
      background: var(--md-scrollbar-track-bg);
      border-radius: var(--md-scrollbar-track-radius);
    }
    ::-webkit-scrollbar-thumb {
      background: var(--md-scrollbar-thumb-bg);
      border-radius: var(--md-scrollbar-thumb-radius);
      transition: background 0.2s ease;
    }
    ::-webkit-scrollbar-thumb:hover {
      background: var(--md-scrollbar-thumb-hover-bg);
    }
    
    /* 滚动条样式 - Firefox */
    * {
      scrollbar-width: thin;
      scrollbar-color: var(--md-scrollbar-thumb-bg) var(--md-scrollbar-track-bg);
    }
  `;

  function _applyTheme() {
    var el = document.getElementById('raincurtain-theme-style');
    if (!el) {
      el = document.createElement('style');
      el.id = 'raincurtain-theme-style';
    }
    el.textContent = cssText;
    // 若尚未插入 DOM 则插入
    if (!el.parentNode) {
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.prepend(el);  // 插入最前端，方便被插件覆盖
      }
    }
  }

  // 立即尝试插入（如果挂载点已就绪）
  var _parent = document.head || document.documentElement;
  if (_parent) {
    _applyTheme();
  } else {
    // AT_DOCUMENT_START 阶段 DOM 完全为空，监听直到 <html>/<head> 出现
    var _obs = new MutationObserver(function() {
      if (document.head || document.documentElement) {
        _obs.disconnect();
        _applyTheme();
      }
    });
    _obs.observe(document, { childList: true, subtree: true });
  }
})();
''';
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  /// 监听键盘事件，F12 / Ctrl+Shift+I / Ctrl+Shift+J 打开 DevTools
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    final isF12 = key == LogicalKeyboardKey.f12;
    final isCtrlShiftI = ctrl && shift && key == LogicalKeyboardKey.keyI;
    final isCtrlShiftJ = ctrl && shift && key == LogicalKeyboardKey.keyJ;

    if (isF12 || isCtrlShiftI || isCtrlShiftJ) {
      webViewController?.openDevTools();
      return true;
    }
    return false;
  }

  /// 打开 DevTools 调试控制台（供外部调用）
  void openDevTools() {
    webViewController?.openDevTools();
  }

  /// 初始化本地通知插件
  Future<void> _initNotifications() async {
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

  /// 注入 JS：覆盖 window.Notification，桥接到 Flutter
  static const String _notificationPolyfillJS = r"""
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

  /// 注入 JS：覆盖 navigator.clipboard，桥接到 Flutter
  static const String _clipboardPolyfillJS = r"""
(function() {
  if (window.__raincurtainClipPatched) return;
  window.__raincurtainClipPatched = true;

  const fakeClipboard = {
    writeText: function(text) {
      return window.flutter_inappwebview.callHandler('raincurtain_clipboard', {
        action: 'write',
        text: text,
      }).then(function() { return undefined; });
    },
    readText: function() {
      return window.flutter_inappwebview.callHandler('raincurtain_clipboard', {
        action: 'read',
      }).then(function(result) { return result || ''; });
    },
  };

  try {
    Object.defineProperty(navigator, 'clipboard', {
      get: function() { return fakeClipboard; },
      configurable: true,
    });
  } catch(e) {
    navigator.clipboard = fakeClipboard;
  }
})();
""";

  /// 注入 JS：拦截 localStorage 操作
  static const String _localStoragePolyfillJS = r"""
(function() {
  if (window.__raincurtainStoragePatched) return;
  window.__raincurtainStoragePatched = true;

  const originalSetItem = localStorage.setItem;
  const originalRemoveItem = localStorage.removeItem;
  const originalClear = localStorage.clear;

  // 拦截 setItem
  localStorage.setItem = function(key, value) {
    originalSetItem.call(localStorage, key, value);
    window.flutter_inappwebview.callHandler('raincurtain_localstorage', {
      action: 'setItem',
      key: key,
      value: value
    }).catch(function(e) {
      console.error('Failed to sync localStorage setItem:', e);
    });
  };

  // 拦截 removeItem
  localStorage.removeItem = function(key) {
    originalRemoveItem.call(localStorage, key);
    window.flutter_inappwebview.callHandler('raincurtain_localstorage', {
      action: 'removeItem',
      key: key
    }).catch(function(e) {
      console.error('Failed to sync localStorage removeItem:', e);
    });
  };

  // 拦截 clear
  localStorage.clear = function() {
    originalClear.call(localStorage);
    window.flutter_inappwebview.callHandler('raincurtain_localstorage', {
      action: 'clear'
    }).catch(function(e) {
      console.error('Failed to sync localStorage clear:', e);
    });
  };

  // 页面加载完成后同步所有数据
  window.addEventListener('load', function() {
    try {
      const data = {};
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key) {
          data[key] = localStorage.getItem(key);
        }
      }
      window.flutter_inappwebview.callHandler('raincurtain_localstorage', {
        action: 'sync',
        data: JSON.stringify(data)
      }).catch(function(e) {
        console.error('Failed to sync localStorage:', e);
      });
    } catch(e) {
      console.error('Failed to collect localStorage data:', e);
    }
  });
})();
""";

  /// 注入 JS：修复 Windows WebView2 滚轮事件问题
  static const String _scrollFixJS = r"""
(function() {
  if (window.__raincurtain_scroll_fix_applied__) return;
  window.__raincurtain_scroll_fix_applied__ = true;

  var SCROLL_STEP = 100;

  document.addEventListener('wheel', function(e) {
    // 检查事件目标是否在声明了 data-raincurtain-wheel-capture 的元素内
    // 如果是,则跳过 scrollFix,让组件自行处理滚轮事件
    var el = e.target;
    while (el) {
      if (el.dataset && el.dataset.raincurtainWheelCapture !== undefined) {
        return;
      }
      el = el.parentElement;
    }

    var target = e.target;
    var scrollable = null;

    // 向上查找第一个可滚动的父元素
    while (target && target !== document.body) {
      var style = window.getComputedStyle(target);
      var overflowY = style.overflowY;
      var canScroll = (overflowY === 'auto' || overflowY === 'scroll');
      if (canScroll && target.scrollHeight > target.clientHeight) {
        scrollable = target;
        break;
      }
      target = target.parentElement;
    }

    if (!scrollable) {
      var root = document.documentElement;
      if (root.scrollHeight > root.clientHeight) {
        scrollable = root;
      }
    }

    if (!scrollable) return;

    e.preventDefault();
    e.stopPropagation();

    var delta = e.deltaY > 0 ? SCROLL_STEP : -SCROLL_STEP;
    scrollable.scrollBy({ top: delta, behavior: 'auto' });
  }, { passive: false, capture: true });
})();
""";

  /// 处理 WebView 触发的下载请求
  /// 支持 data: URI（base64 内联数据）和普通 http/https URL
  Future<void> _handleDownload({
    required String url,
    String? suggestedFilename,
    String? mimeType,
  }) async {
    try {
      // 确定保存目录：优先使用外部存储 Downloads，回退到应用文档目录
      Directory saveDir;
      if (Platform.isAndroid) {
        // Android 外部存储 Downloads 目录
        saveDir = Directory('/storage/emulated/0/Download');
        if (!await saveDir.exists()) {
          saveDir = await getApplicationDocumentsDirectory();
        }
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }

      final filename = suggestedFilename?.isNotEmpty == true
          ? suggestedFilename!
          : 'download_${DateTime.now().millisecondsSinceEpoch}';
      final savePath = '${saveDir.path}/$filename';

      if (url.startsWith('data:')) {
        // 处理 data: URI（如 data:text/plain;base64,... 或 data:text/plain;charset=utf-8,...）
        final commaIdx = url.indexOf(',');
        if (commaIdx == -1) return;
        final header = url.substring(5, commaIdx); // 去掉 "data:"
        final body = url.substring(commaIdx + 1);
        final isBase64 = header.contains(';base64');
        final bytes = isBase64
            ? base64Decode(body)
            : utf8.encode(Uri.decodeComponent(body));
        await File(savePath).writeAsBytes(bytes);
      } else {
        // 普通 HTTP/HTTPS URL：用 HttpClient 下载
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        final bytes = await consolidateHttpClientResponseBytes(response);
        await File(savePath).writeAsBytes(bytes);
        client.close();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已下载到: $savePath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 下载失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 假设 InAppLocalhostServer 运行在 8080 端口
    final url = 'http://localhost:8080/${widget.plugin.entryPath}';

    return Stack(
      children: [
        // WebView 主体
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialUserScripts: UnmodifiableListView([
            // 注入当前应用的主题色系和基础样式
            UserScript(
              source: _generateThemeJS(Theme.of(context)),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // Windows 平台不注入通知 polyfill，使用原生 Web Notification API
            if (!Platform.isWindows)
              UserScript(
                source: _notificationPolyfillJS,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            UserScript(
              source: _clipboardPolyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 LocalStorage 拦截脚本
            UserScript(
              source: _localStoragePolyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // Windows 平台注入滚动修复脚本，解决 WebView2 滚轮事件问题
            if (Platform.isWindows)
              UserScript(
                source: _scrollFixJS,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
          ]),
          initialSettings: InAppWebViewSettings(
            isInspectable: true,
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            javaScriptCanOpenWindowsAutomatically: true,
            // 地理位置放行
            geolocationEnabled: true,
            // Android 特有：允许混合内容（http 与 https 混用）
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            // Android 特有：允许通用访问（跨域 file:// 等）
            allowUniversalAccessFromFileURLs: true,
            allowFileAccessFromFileURLs: true,
            // 允许内容 URL 访问
            allowContentAccess: true,
            // 允许文件访问
            allowFileAccess: true,
            // 关闭安全浏览（避免拦截本地 localhost 内容）
            safeBrowsingEnabled: false,
            // 允许第三方 Cookie（Android 5+）
            thirdPartyCookiesEnabled: true,
            // 支持 DOM Storage
            domStorageEnabled: true,
            // 数据库存储
            databaseEnabled: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            
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
            
            // 注册 JS Handler：接收来自 WebView 的剪贴板读写请求
            controller.addJavaScriptHandler(
              handlerName: 'raincurtain_clipboard',
              callback: (args) async {
                if (args.isEmpty) return null;
                final data = args[0] as Map<dynamic, dynamic>;
                final action = data['action'] as String? ?? '';
                if (action == 'write') {
                  final text = (data['text'] as String?) ?? '';
                  await Clipboard.setData(ClipboardData(text: text));
                  return null;
                } else if (action == 'read') {
                  final clipData = await Clipboard.getData(Clipboard.kTextPlain);
                  return clipData?.text ?? '';
                }
                return null;
              },
            );
            
            // 注册 JS Handler：接收来自 WebView 的 LocalStorage 操作
            controller.addJavaScriptHandler(
              handlerName: 'raincurtain_localstorage',
              callback: (args) async {
                if (args.isEmpty) return null;
                final data = args[0] as Map<dynamic, dynamic>;
                final action = data['action'] as String? ?? '';
                
                if (!context.mounted) return null;
                final dataManager = context.read<PluginDataManager>();
                if (!dataManager.isInit) return null;
                
                final pluginId = widget.plugin.id;
                
                try {
                  switch (action) {
                    case 'sync':
                      // 同步所有 LocalStorage 数据
                      final storageData = jsonDecode(data['data'] as String) as Map<String, dynamic>;
                      await dataManager.localStorageManager.saveLocalStorage(
                        pluginId,
                        storageData,
                      );
                      break;
                    case 'setItem':
                      // 更新单个键值
                      final key = data['key'] as String;
                      final value = data['value'] as String;
                      await dataManager.localStorageManager.setItem(
                        pluginId,
                        key,
                        value,
                      );
                      break;
                    case 'removeItem':
                      // 删除单个键
                      final key = data['key'] as String;
                      await dataManager.localStorageManager.removeItem(
                        pluginId,
                        key,
                      );
                      break;
                    case 'clear':
                      // 清空所有数据
                      await dataManager.localStorageManager.clearLocalStorage(pluginId);
                      break;
                  }
                } catch (e) {
                  debugPrint('LocalStorage handler error: $e');
                }
                
                return null;
              },
            );
            
            // 加载历史 Cookie
            final url = WebUri('http://localhost:8080/${widget.plugin.entryPath}');
            if (context.mounted) {
              final dataManager = context.read<PluginDataManager>();
              if (dataManager.isInit) {
                dataManager.cookieManager.loadCookiesForPlugin(
                  widget.plugin.id,
                  url,
                );
              }
            }
          },
          onProgressChanged: (controller, p) {
            setState(() {
              progress = p / 100;
            });
          },
          onPermissionRequest: (controller, request) async {
            // 核心逻辑：自动无条件放行所有前端 JS 权限指令
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            return GeolocationPermissionShowPromptResponse(
              origin: origin,
              allow: true,
              retain: true,
            );
          },
          onLoadStop: (controller, url) async {
            // 页面加载完成后保存 Cookie
            if (url != null && context.mounted) {
              final dataManager = context.read<PluginDataManager>();
              if (dataManager.isInit) {
                await dataManager.cookieManager.saveCookiesForPlugin(
                  widget.plugin.id,
                  url,
                );
              }
            }
          },
          onDownloadStartRequest: (controller, downloadStartRequest) async {
            // 拦截 WebView 下载请求，用原生方式保存文件
            _handleDownload(
              url: downloadStartRequest.url.toString(),
              suggestedFilename: downloadStartRequest.suggestedFilename,
              mimeType: downloadStartRequest.mimeType,
            );
          },
          onReceivedError: (controller, request, error) {
            setState(() {
              hasError = true;
              errorMessage = '加载失败: ${error.description} (错误码: ${error.type})';
            });
          },
          onReceivedHttpError: (controller, request, errorResponse) {
            // 仅当主框架请求失败时才显示错误，忽略子资源（如 favicon、API 等）的 404
            if ((request.isForMainFrame ?? false) &&
                errorResponse.statusCode != null &&
                errorResponse.statusCode! >= 400) {
              setState(() {
                hasError = true;
                errorMessage = 'HTTP 错误: ${errorResponse.statusCode} - ${errorResponse.reasonPhrase}';
              });
            }
          },
        ),
        // 加载进度指示器
        if (progress < 1.0 && !hasError)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: colorScheme.primary,
              minHeight: 3,
            ),
          ),
        // 错误状态显示
        if (hasError)
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载失败',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage ?? '未知错误',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        hasError = false;
                        errorMessage = null;
                        progress = 0;
                      });
                      webViewController?.reload();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
