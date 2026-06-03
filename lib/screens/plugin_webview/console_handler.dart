import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/console_manager.dart';

/// Console 拦截相关的 JS polyfill 和 Handler 注册
///
/// 通过 JS polyfill 代理 console.log/info/warn/error/debug 方法，
/// 在 JS 侧通过 Error().stack 提取调用位置（文件名:行号），
/// 通过 JavaScriptHandler 传回 Dart 侧记录到 ConsoleManager。
mixin ConsoleMixin {
  /// 注入 JS：覆盖 console 方法，拦截输出并传递给 Flutter
  static const String polyfillJS = r"""
(function() {
  if (window.__raincurtainConsolePatched) return;
  window.__raincurtainConsolePatched = true;

  var _origLog   = console.log.bind(console);
  var _origInfo  = console.info.bind(console);
  var _origWarn  = console.warn.bind(console);
  var _origError = console.error.bind(console);
  var _origDebug = console.debug.bind(console);

  // 从 Error().stack 中提取调用者的源码位置
  function _extractSource() {
    try {
      var stack = new Error().stack || '';
      var lines = stack.split('\n');
      // 跳过 Error 构造、_extractSource、代理函数本身，取第 4 行
      // 堆栈格式示例:
      //   Chrome/WebView2: "    at Object.log (main.js:129:15)"
      //   Android WebView: "    at main.js:129:15"
      for (var i = 3; i < lines.length; i++) {
        var line = lines[i];
        if (!line) continue;
        // 跳过 polyfill 自身的帧
        if (line.indexOf('__raincurtainConsolePatched') !== -1) continue;

        // 匹配 "(file:line:col)" 或 "at file:line:col" 格式
        var m = line.match(/\(([^)]+):(\d+):\d+\)/) ||
                line.match(/at\s+([^\s]+):(\d+):\d+/) ||
                line.match(/([^\s@]+):(\d+):\d+/);
        if (m) {
          var file = m[1];
          // 仅保留文件名（去掉路径前缀）
          var lastSlash = file.lastIndexOf('/');
          if (lastSlash !== -1) file = file.substring(lastSlash + 1);
          return file + ':' + m[2];
        }
      }
    } catch(e) {}
    return null;
  }

  // 将参数序列化为字符串
  function _argsToString(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var v = args[i];
      if (v === undefined) {
        parts.push('undefined');
      } else if (v === null) {
        parts.push('null');
      } else if (typeof v === 'object') {
        try { parts.push(JSON.stringify(v, null, 2)); }
        catch(e) { parts.push(String(v)); }
      } else {
        parts.push(String(v));
      }
    }
    return parts.join(' ');
  }

  function _makeProxy(level, origFn) {
    return function() {
      // 调用原始方法（保留 DevTools 中的输出）
      origFn.apply(console, arguments);
      // 提取调用位置并发送给 Flutter
      var source = _extractSource();
      var message = _argsToString(arguments);
      try {
        window.flutter_inappwebview.callHandler('raincurtain_console', {
          level: level,
          message: message,
          source: source
        });
      } catch(e) {}
    };
  }

  console.log   = _makeProxy('log',   _origLog);
  console.info  = _makeProxy('info',  _origInfo);
  console.warn  = _makeProxy('warn',  _origWarn);
  console.error = _makeProxy('error', _origError);
  console.debug = _makeProxy('debug', _origDebug);
})();
""";

  /// 注册 console handler
  void registerConsoleHandlers(
    InAppWebViewController controller,
    ConsoleManager consoleManager,
  ) {
    controller.addJavaScriptHandler(
      handlerName: 'raincurtain_console',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<dynamic, dynamic>;
        final levelStr = data['level'] as String? ?? 'log';
        final message = data['message'] as String? ?? '';
        final source = data['source'] as String?;

        final level = _parseLevel(levelStr);
        consoleManager.addMessage(level, message, source: source);
      },
    );
  }

  /// 将 JS 传来的级别字符串解析为 ConsoleLevel
  ConsoleLevel _parseLevel(String level) {
    switch (level) {
      case 'log':
        return ConsoleLevel.log;
      case 'info':
        return ConsoleLevel.info;
      case 'warn':
        return ConsoleLevel.warn;
      case 'error':
        return ConsoleLevel.error;
      case 'debug':
        return ConsoleLevel.debug;
      default:
        return ConsoleLevel.log;
    }
  }
}
