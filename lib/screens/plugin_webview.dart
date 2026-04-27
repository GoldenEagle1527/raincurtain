import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/plugin_data_manager.dart';

/// 网络请求性能指标
class _FetchMetrics {
  final DateTime startTime;
  final String url;
  final String method;
  int? statusCode;
  int? responseSize;
  String? error;
  
  _FetchMetrics({
    required this.url,
    required this.method,
  }) : startTime = DateTime.now();
  
  Duration get duration => DateTime.now().difference(startTime);
  
  void complete(int status, int size) {
    statusCode = status;
    responseSize = size;
  }
  
  void fail(String err) {
    error = err;
  }
  
  void log() {
    if (error != null) {
      debugPrint('[RainCurtain Fetch] ❌ $method $url\n  Error: $error\n  Duration: ${duration.inMilliseconds}ms');
    } else {
      debugPrint('[RainCurtain Fetch] ✅ $method $url\n  Status: $statusCode\n  Size: ${responseSize ?? 0} bytes\n  Duration: ${duration.inMilliseconds}ms');
    }
  }
}

/// HTTP 响应缓存条目
class _CachedResponse {
  final int statusCode;
  final String? reasonPhrase;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final DateTime cachedAt;
  final Duration maxAge;

  _CachedResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.bodyBytes,
    required this.maxAge,
  }) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > maxAge;

  /// 从响应头解析 max-age，默认 60 秒
  static Duration _parseMaxAge(Map<String, String> headers) {
    final cc = headers['cache-control'] ?? headers['Cache-Control'] ?? '';
    final match = RegExp(r'max-age=(\d+)').firstMatch(cc);
    if (match != null) {
      final seconds = int.tryParse(match.group(1) ?? '');
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    // no-store / no-cache → don't cache
    if (cc.contains('no-store') || cc.contains('no-cache')) {
      return Duration.zero;
    }
    return const Duration(seconds: 60);
  }

  static _CachedResponse? fromResponse(http.Response response) {
    final headers = response.headers;
    final maxAge = _parseMaxAge(headers);
    if (maxAge == Duration.zero) return null; // not cacheable
    return _CachedResponse(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: headers,
      bodyBytes: response.bodyBytes,
      maxAge: maxAge,
    );
  }
}

/// LRU 请求缓存（仅缓存 GET 请求）
class _RequestCache {
  static const int _maxEntries = 50;
  // LinkedHashMap preserves insertion order; we remove the oldest entry on overflow
  final LinkedHashMap<String, _CachedResponse> _store =
      LinkedHashMap<String, _CachedResponse>();

  _CachedResponse? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    // Move to end (most-recently-used)
    _store.remove(key);
    _store[key] = entry;
    return entry;
  }

  void put(String key, _CachedResponse entry) {
    _store.remove(key); // reset position
    if (_store.length >= _maxEntries) {
      _store.remove(_store.keys.first); // evict LRU
    }
    _store[key] = entry;
  }

  void clear() => _store.clear();
}

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
  
  // 网络请求管理：支持请求取消
  final Map<String, http.Client> _activeRequests = {};
  
  // 性能监控：记录请求指标
  final Map<String, _FetchMetrics> _requestMetrics = {};

  // GET 请求缓存（LRU，最多 50 条，按 Cache-Control 设置 TTL）
  final _RequestCache _requestCache = _RequestCache();

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

  /// 注入 JS：拦截跨域 fetch/XMLHttpRequest，请求改由 Flutter 侧发起
  static const String _fetchPolyfillJS = r"""
(function() {
  if (window.__raincurtainFetchPatched) return;
  window.__raincurtainFetchPatched = true;

  var originalFetch = window.fetch ? window.fetch.bind(window) : null;
  var OriginalXHR = window.XMLHttpRequest;
  var localhostOrigin = 'http://localhost:8080';

  // 生成唯一请求 ID (简化版 UUID v4)
  function generateRequestId() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0;
      var v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  function isLocalRequest(url) {
    if (!url) return true;
    if (url.indexOf('data:') === 0 || url.indexOf('blob:') === 0) return true;
    if (url.indexOf('/') === 0) return true;
    if (url.indexOf(localhostOrigin) === 0) return true;
    try {
      var resolved = new URL(url, window.location.href);
      return resolved.origin === window.location.origin;
    } catch (_) {
      return true;
    }
  }

  function headersToObject(headers) {
    var result = {};
    if (!headers) return result;

    if (typeof Headers !== 'undefined' && headers instanceof Headers) {
      headers.forEach(function(value, key) {
        result[key] = value;
      });
      return result;
    }

    if (Array.isArray(headers)) {
      headers.forEach(function(entry) {
        if (Array.isArray(entry) && entry.length >= 2) {
          result[String(entry[0])] = String(entry[1]);
        }
      });
      return result;
    }

    Object.keys(headers).forEach(function(key) {
      result[key] = String(headers[key]);
    });
    return result;
  }

  // 将 File/Blob 转为 base64 字符串（不含 data-URL 前缀）
  function blobToBase64(blob) {
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onloadend = function() {
        var result = reader.result || '';
        var commaIndex = result.indexOf(',');
        resolve(commaIndex >= 0 ? result.substring(commaIndex + 1) : '');
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  function arrayBufferToBase64(buffer) {
    var bytes = new Uint8Array(buffer);
    var binary = '';
    var chunkSize = 0x8000;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      var chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, chunk);
    }
    return btoa(binary);
  }

  function base64ToUint8Array(base64) {
    var binary = atob(base64 || '');
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  // 规范化请求体：支持 File/Blob 作为 multipart 字段
  async function normalizeBody(body) {
    if (body == null) return null;
    if (typeof body === 'string') {
      return { kind: 'text', data: body };
    }
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      return { kind: 'text', data: body.toString() };
    }
    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      var entries = [];
      var filePromises = [];
      body.forEach(function(value, key) {
        if (typeof File !== 'undefined' && value instanceof File) {
          var idx = entries.length;
          entries.push({ key: key, type: 'file', filename: value.name, contentType: value.type || 'application/octet-stream', data: null });
          filePromises.push(
            blobToBase64(value).then(function(b64) { entries[idx].data = b64; })
          );
        } else if (typeof Blob !== 'undefined' && value instanceof Blob) {
          var idx2 = entries.length;
          entries.push({ key: key, type: 'file', filename: 'blob', contentType: value.type || 'application/octet-stream', data: null });
          filePromises.push(
            blobToBase64(value).then(function(b64) { entries[idx2].data = b64; })
          );
        } else {
          entries.push({ key: key, type: 'text', data: String(value) });
        }
      });
      if (filePromises.length > 0) {
        await Promise.all(filePromises);
      }
      return { kind: 'form-data', data: JSON.stringify(entries) };
    }
    if (typeof Blob !== 'undefined' && body instanceof Blob) {
      return { kind: 'base64', data: await blobToBase64(body) };
    }
    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
      return { kind: 'base64', data: arrayBufferToBase64(body) };
    }
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(body)) {
      return {
        kind: 'base64',
        data: arrayBufferToBase64(body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)),
      };
    }
    return { kind: 'text', data: String(body) };
  }

  function buildResponse(result, url) {
    var headers = new Headers(result.headers || {});
    var body = result.bodyBase64 != null
      ? base64ToUint8Array(result.bodyBase64)
      : (result.bodyText || '');
    var response = new Response(body, {
      status: result.status,
      statusText: result.statusText || '',
      headers: headers,
    });
    try {
      Object.defineProperty(response, 'url', {
        value: url,
        configurable: true,
      });
    } catch (_) {}
    return response;
  }

  // 构建一个流式 Response，Flutter 通过 window.__rc_stream_<id> 推送数据块
  function buildStreamingResponse(meta, url, requestId) {
    var responseHeaders = new Headers(meta.headers || {});
    var streamController;
    var stream = new ReadableStream({
      start: function(controller) {
        streamController = controller;
        // 注册全局回调，Flutter 通过 evaluateJavascript 调用
        window['__rc_stream_chunk_' + requestId] = function(base64Chunk) {
          try {
            controller.enqueue(base64ToUint8Array(base64Chunk));
          } catch (_) {}
        };
        window['__rc_stream_done_' + requestId] = function() {
          try { controller.close(); } catch (_) {}
          delete window['__rc_stream_chunk_' + requestId];
          delete window['__rc_stream_done_' + requestId];
          delete window['__rc_stream_error_' + requestId];
        };
        window['__rc_stream_error_' + requestId] = function(msg) {
          try { controller.error(new TypeError(msg)); } catch (_) {}
          delete window['__rc_stream_chunk_' + requestId];
          delete window['__rc_stream_done_' + requestId];
          delete window['__rc_stream_error_' + requestId];
        };
      },
      cancel: function() {
        // User cancelled the reader — abort the Flutter-side request
        window.flutter_inappwebview && window.flutter_inappwebview.callHandler('raincurtain_abort', { requestId: requestId }).catch(function(){});
        delete window['__rc_stream_chunk_' + requestId];
        delete window['__rc_stream_done_' + requestId];
        delete window['__rc_stream_error_' + requestId];
      },
    });

    var response = new Response(stream, {
      status: meta.status,
      statusText: meta.statusText || '',
      headers: responseHeaders,
    });
    try {
      Object.defineProperty(response, 'url', { value: url, configurable: true });
    } catch (_) {}
    return response;
  }

  async function interceptedFetch(resource, init) {
    var request = resource instanceof Request ? resource : null;
    var url = request ? request.url : String(resource);

    if (isLocalRequest(url) || !window.flutter_inappwebview) {
      if (!originalFetch) {
        throw new Error('Native fetch is unavailable');
      }
      return originalFetch(resource, init);
    }

    var method = 'GET';
    var headers = {};
    var body = null;
    var signal = null;

    if (request) {
      method = request.method || method;
      headers = headersToObject(request.headers);
      signal = request.signal;
      if (!init || init.body === undefined) {
        body = await normalizeBody(await request.clone().arrayBuffer());
      }
    }

    if (init) {
      if (init.method) method = init.method;
      if (init.headers) headers = headersToObject(init.headers);
      if (init.body !== undefined) body = await normalizeBody(init.body);
      if (init.signal) signal = init.signal;
    }

    // 生成请求 ID 用于取消
    var requestId = generateRequestId();

    // 如果有 AbortSignal，监听取消事件
    if (signal) {
      if (signal.aborted) {
        throw new DOMException('The operation was aborted.', 'AbortError');
      }
      signal.addEventListener('abort', function() {
        window.flutter_inappwebview.callHandler('raincurtain_abort', {
          requestId: requestId,
        }).catch(function(e) {
          console.warn('Failed to abort request:', e);
        });
      });
    }

    // 判断是否请求流式响应：Accept 含 text/event-stream 或显式 rc-stream 头
    var wantsStream = (headers['accept'] || headers['Accept'] || '').indexOf('text/event-stream') >= 0
      || headers['x-rc-stream'] === '1';

    var result = await window.flutter_inappwebview.callHandler('raincurtain_fetch', {
      requestId: requestId,
      url: url,
      method: method,
      headers: headers,
      body: body,
      stream: wantsStream,
    });

    if (!result || result.ok !== true) {
      throw new TypeError((result && result.error) || 'Network request failed');
    }

    // 如果 Flutter 确认以流式方式响应
    if (result.streaming) {
      return buildStreamingResponse(result, url, requestId);
    }

    return buildResponse(result, url);
  }

  if (originalFetch) {
    window.fetch = function(resource, init) {
      return interceptedFetch(resource, init);
    };
  }

  if (OriginalXHR) {
    function RainCurtainXHR() {
      this._nativeXhr = new OriginalXHR();
      this._method = 'GET';
      this._url = '';
      this._async = true;
      this._headers = {};
      this._body = null;
      this._intercept = false;
      this._responseHeaders = {};
      this.readyState = 0;
      this.status = 0;
      this.statusText = '';
      this.response = null;
      this.responseText = '';
      this.responseType = '';
      this.timeout = 0;
      this.withCredentials = false;
      this.onreadystatechange = null;
      this.onload = null;
      this.onerror = null;
      this.onabort = null;
      this.ontimeout = null;
      this.onloadend = null;
      this.onprogress = null;
      this._bindNativeEvents();
    }

    RainCurtainXHR.UNSENT = 0;
    RainCurtainXHR.OPENED = 1;
    RainCurtainXHR.HEADERS_RECEIVED = 2;
    RainCurtainXHR.LOADING = 3;
    RainCurtainXHR.DONE = 4;

    RainCurtainXHR.prototype._bindNativeEvents = function() {
      var self = this;
      var nativeXhr = this._nativeXhr;
      nativeXhr.onreadystatechange = function() {
        if (self._intercept) return;
        self.readyState = nativeXhr.readyState;
        if (nativeXhr.readyState >= 2) {
          self.status = nativeXhr.status;
          self.statusText = nativeXhr.statusText;
        }
        if (nativeXhr.readyState === 4) {
          self.response = nativeXhr.response;
          self.responseText = nativeXhr.responseText;
        }
        self._emit('readystatechange');
      };
      nativeXhr.onload = function(event) {
        if (self._intercept) return;
        self._emit('load', event);
        self._emit('loadend', event);
      };
      nativeXhr.onerror = function(event) {
        if (self._intercept) return;
        self._emit('error', event);
        self._emit('loadend', event);
      };
      nativeXhr.onabort = function(event) {
        if (self._intercept) return;
        self._emit('abort', event);
        self._emit('loadend', event);
      };
      nativeXhr.ontimeout = function(event) {
        if (self._intercept) return;
        self._emit('timeout', event);
        self._emit('loadend', event);
      };
      nativeXhr.onprogress = function(event) {
        if (self._intercept) return;
        self._emit('progress', event);
      };
    };

    RainCurtainXHR.prototype._emit = function(type, event) {
      var handler = this['on' + type];
      if (typeof handler === 'function') {
        handler.call(this, event);
      }
    };

    RainCurtainXHR.prototype.open = function(method, url, async, user, password) {
      this._method = method || 'GET';
      this._url = String(url);
      this._async = async !== false;
      this._intercept = !isLocalRequest(this._url) && !!window.flutter_inappwebview;
      this.readyState = 1;
      this._emit('readystatechange');
      if (!this._intercept) {
        this._nativeXhr.open(method, url, async, user, password);
      }
    };

    RainCurtainXHR.prototype.setRequestHeader = function(name, value) {
      this._headers[name] = String(value);
      if (!this._intercept) {
        this._nativeXhr.setRequestHeader(name, value);
      }
    };

    RainCurtainXHR.prototype.getAllResponseHeaders = function() {
      if (!this._intercept) {
        return this._nativeXhr.getAllResponseHeaders();
      }
      return Object.keys(this._responseHeaders).map(function(key) {
        return key + ': ' + String(this._responseHeaders[key]);
      }, this).join('\r\n');
    };

    RainCurtainXHR.prototype.getResponseHeader = function(name) {
      if (!this._intercept) {
        return this._nativeXhr.getResponseHeader(name);
      }
      var lowerName = String(name).toLowerCase();
      var keys = Object.keys(this._responseHeaders);
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].toLowerCase() === lowerName) {
          return String(this._responseHeaders[keys[i]]);
        }
      }
      return null;
    };

    RainCurtainXHR.prototype.abort = function() {
      if (!this._intercept) {
        return this._nativeXhr.abort();
      }
      this.readyState = 4;
      this._emit('abort');
      this._emit('loadend');
    };

    RainCurtainXHR.prototype.overrideMimeType = function(mime) {
      if (!this._intercept && this._nativeXhr.overrideMimeType) {
        this._nativeXhr.overrideMimeType(mime);
      }
    };

    RainCurtainXHR.prototype.send = async function(body) {
      if (!this._intercept) {
        this._nativeXhr.responseType = this.responseType;
        this._nativeXhr.timeout = this.timeout;
        this._nativeXhr.withCredentials = this.withCredentials;
        return this._nativeXhr.send(body);
      }

      try {
        this._body = await normalizeBody(body);
        var result = await window.flutter_inappwebview.callHandler('raincurtain_fetch', {
          url: this._url,
          method: this._method,
          headers: this._headers,
          body: this._body,
          stream: false,
        });

        if (!result || result.ok !== true) {
          throw new Error((result && result.error) || 'Network request failed');
        }

        this.status = result.status;
        this.statusText = result.statusText || '';
        this._responseHeaders = result.headers || {};
        this.readyState = 2;
        this._emit('readystatechange');
        this.readyState = 3;
        this._emit('readystatechange');

        if (this.responseType === 'arraybuffer' || this.responseType === 'blob') {
          var bytes = base64ToUint8Array(result.bodyBase64 || '');
          this.response = this.responseType === 'blob' ? new Blob([bytes]) : bytes.buffer;
          this.responseText = '';
        } else {
          this.responseText = result.bodyText || '';
          this.response = this.responseText;
        }

        this.readyState = 4;
        this._emit('readystatechange');
        this._emit('load');
        this._emit('loadend');
      } catch (error) {
        this.readyState = 4;
        this.status = 0;
        this.statusText = '';
        this.response = null;
        this.responseText = '';
        this._emit('readystatechange');
        this._emit('error', error);
        this._emit('loadend', error);
      }
    };

    Object.defineProperty(RainCurtainXHR.prototype, 'responseURL', {
      get: function() {
        return this._url;
      },
    });

    window.XMLHttpRequest = RainCurtainXHR;
  }
})();
""";

  /// 解析 MIME 类型字符串为 MediaType（仅用于 multipart 文件上传）
  http_parser.MediaType _parseMediaType(String contentType) {
    try {
      return http_parser.MediaType.parse(contentType);
    } catch (_) {
      return http_parser.MediaType('application', 'octet-stream');
    }
  }

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
            // 注入网络请求拦截脚本，跨域请求改由 Flutter 侧发起
            UserScript(
              source: _fetchPolyfillJS,
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

            // 注册 JS Handler：接收来自 WebView 的跨域网络请求，由 Flutter 侧发起
            controller.addJavaScriptHandler(
              handlerName: 'raincurtain_fetch',
              callback: (args) async {
                if (args.isEmpty) {
                  return {
                    'ok': false,
                    'error': 'Missing request payload',
                  };
                }

                // 提取请求 ID
                final data = args[0] as Map<dynamic, dynamic>;
                final requestId = data['requestId'] as String?;
                final wantsStream = data['stream'] == true;
                
                // 创建性能指标
                final url = (data['url'] as String? ?? '').trim();
                final method = (data['method'] as String? ?? 'GET').toUpperCase();
                final metrics = _FetchMetrics(url: url, method: method);
                if (requestId != null) {
                  _requestMetrics[requestId] = metrics;
                }

                try {
                  if (url.isEmpty) {
                    metrics.fail('Missing request url');
                    metrics.log();
                    return {
                      'ok': false,
                      'error': 'Missing request url',
                    };
                  }

                  final rawHeaders = data['headers'];
                  final headers = <String, String>{};
                  if (rawHeaders is Map) {
                    rawHeaders.forEach((key, value) {
                      headers[key.toString()] = value.toString();
                    });
                  }

                  // ── 构建请求体 ──────────────────────────────────────────
                  final rawBody = data['body'];
                  final uri = Uri.parse(url);
                  http.BaseRequest request;

                  if (rawBody is Map) {
                    final bodyMap = Map<dynamic, dynamic>.from(rawBody);
                    final kind = (bodyMap['kind'] as String? ?? 'text').trim();
                    final payload = bodyMap['data'];

                    if (kind == 'form-data') {
                      // FormData entries: [{key, type, data, filename?, contentType?}]
                      final entries = jsonDecode((payload as String?) ?? '[]');
                      final multipart = http.MultipartRequest(method, uri);
                      multipart.headers.addAll(headers);
                      if (entries is List) {
                        for (final entry in entries) {
                          if (entry is! Map) continue;
                          final key = entry['key']?.toString() ?? '';
                          final type = entry['type']?.toString() ?? 'text';
                          if (type == 'file') {
                            // File field encoded as base64
                            final b64 = entry['data']?.toString() ?? '';
                            final bytes = base64Decode(b64);
                            final filename = entry['filename']?.toString() ?? 'file';
                            final contentType = entry['contentType']?.toString() ?? 'application/octet-stream';
                            multipart.files.add(http.MultipartFile.fromBytes(
                              key,
                              bytes,
                              filename: filename,
                              contentType: _parseMediaType(contentType),
                            ));
                          } else {
                            // Text field
                            multipart.fields[key] = entry['data']?.toString() ?? '';
                          }
                        }
                      }
                      request = multipart;
                    } else {
                      // Plain request
                      final plainRequest = http.Request(method, uri);
                      plainRequest.headers.addAll(headers);
                      switch (kind) {
                        case 'base64':
                          plainRequest.bodyBytes = base64Decode((payload as String?) ?? '');
                          break;
                        case 'text':
                        default:
                          plainRequest.body = payload?.toString() ?? '';
                          break;
                      }
                      request = plainRequest;
                    }
                  } else {
                    // No body
                    final plainRequest = http.Request(method, uri);
                    plainRequest.headers.addAll(headers);
                    request = plainRequest;
                  }

                  // ── 缓存检查（仅 GET 非流式）─────────────────────────
                  if (method == 'GET' && !wantsStream && request is http.Request && request.bodyBytes.isEmpty) {
                    final cached = _requestCache.get(url);
                    if (cached != null) {
                      debugPrint('[RainCurtain Fetch] 💾 Cache hit: $url');
                      return {
                        'ok': true,
                        'status': cached.statusCode,
                        'statusText': cached.reasonPhrase ?? '',
                        'headers': cached.headers,
                        'bodyText': utf8.decode(cached.bodyBytes, allowMalformed: true),
                        'bodyBase64': base64Encode(cached.bodyBytes),
                        'streaming': false,
                      };
                    }
                  }

                  // ── 发送请求 ──────────────────────────────────────────
                  final client = http.Client();
                  if (requestId != null) {
                    _activeRequests[requestId] = client;
                  }

                  try {
                    final streamedResponse = await client.send(request);

                    if (wantsStream) {
                      // ── 流式响应：立即返回元数据，后台推送数据块 ────
                      final responseHeaders = streamedResponse.headers;
                      metrics.complete(streamedResponse.statusCode, 0);
                      metrics.log();

                      // 在后台监听数据流并推送到 JS 侧
                      if (requestId != null && webViewController != null) {
                        final rcId = requestId; // capture
                        final wvc = webViewController!;
                        streamedResponse.stream.listen(
                          (chunk) {
                            final b64 = base64Encode(chunk);
                            // Push chunk to JS via evaluateJavascript
                            wvc.evaluateJavascript(
                              source: 'if(window["__rc_stream_chunk_$rcId"])window["__rc_stream_chunk_$rcId"]("$b64");',
                            );
                          },
                          onDone: () {
                            wvc.evaluateJavascript(
                              source: 'if(window["__rc_stream_done_$rcId"])window["__rc_stream_done_$rcId"]();',
                            );
                            _activeRequests.remove(rcId);
                            _requestMetrics.remove(rcId);
                            client.close();
                          },
                          onError: (e) {
                            final msg = e.toString().replaceAll('"', '\\"');
                            wvc.evaluateJavascript(
                              source: 'if(window["__rc_stream_error_$rcId"])window["__rc_stream_error_$rcId"]("$msg");',
                            );
                            _activeRequests.remove(rcId);
                            _requestMetrics.remove(rcId);
                            client.close();
                          },
                          cancelOnError: true,
                        );
                      } else {
                        // No requestId or controller — fall back to buffered
                        final response = await http.Response.fromStream(streamedResponse);
                        metrics.complete(response.statusCode, response.bodyBytes.length);
                        client.close();
                        return {
                          'ok': true,
                          'status': response.statusCode,
                          'statusText': response.reasonPhrase ?? '',
                          'headers': response.headers,
                          'bodyText': utf8.decode(response.bodyBytes, allowMalformed: true),
                          'bodyBase64': base64Encode(response.bodyBytes),
                          'streaming': false,
                        };
                      }

                      return {
                        'ok': true,
                        'status': streamedResponse.statusCode,
                        'statusText': streamedResponse.reasonPhrase ?? '',
                        'headers': responseHeaders,
                        'streaming': true,
                      };
                    } else {
                      // ── 缓冲响应（现有行为）──────────────────────────
                      final response = await http.Response.fromStream(streamedResponse);
                      
                      // 记录性能指标
                      metrics.complete(response.statusCode, response.bodyBytes.length);
                      metrics.log();

                      // 写入缓存（仅 GET）
                      if (method == 'GET') {
                        final entry = _CachedResponse.fromResponse(response);
                        if (entry != null) {
                          _requestCache.put(url, entry);
                        }
                      }
                      
                      return {
                        'ok': true,
                        'status': response.statusCode,
                        'statusText': response.reasonPhrase ?? '',
                        'headers': response.headers,
                        'bodyText': utf8.decode(response.bodyBytes, allowMalformed: true),
                        'bodyBase64': base64Encode(response.bodyBytes),
                        'streaming': false,
                      };
                    }
                  } finally {
                    if (!wantsStream) {
                      // For streaming, cleanup is done in stream callbacks
                      client.close();
                      if (requestId != null) {
                        _activeRequests.remove(requestId);
                        _requestMetrics.remove(requestId);
                      }
                    }
                  }
                } catch (e) {
                  metrics.fail(e.toString());
                  metrics.log();
                  return {
                    'ok': false,
                    'error': e.toString(),
                  };
                } finally {
                  if (requestId != null) {
                    _requestMetrics.remove(requestId);
                  }
                }
              },
            );

            // 注册 JS Handler：取消进行中的网络请求
            controller.addJavaScriptHandler(
              handlerName: 'raincurtain_abort',
              callback: (args) async {
                if (args.isEmpty) return null;
                
                try {
                  final data = args[0] as Map<dynamic, dynamic>;
                  final requestId = data['requestId'] as String?;
                  
                  if (requestId != null) {
                    final client = _activeRequests.remove(requestId);
                    if (client != null) {
                      client.close();
                      debugPrint('[RainCurtain Fetch] ⚠️ Request aborted: $requestId');
                    }
                    _requestMetrics.remove(requestId);
                  }
                } catch (e) {
                  debugPrint('Abort handler error: $e');
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
