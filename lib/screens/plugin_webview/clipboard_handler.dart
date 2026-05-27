import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 剪贴板相关的 JS polyfill 和 Handler 注册
mixin ClipboardMixin {
  /// 注入 JS：覆盖 navigator.clipboard，桥接到 Flutter
  static const String polyfillJS = r"""
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

  /// 注册剪贴板 Handler
  void registerClipboardHandlers(InAppWebViewController controller) {
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
  }
}
