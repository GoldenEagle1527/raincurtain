import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 屏幕方向控制 — 系统级真旋转
///
/// 通过 SystemChrome.setPreferredOrientations 让 Android 系统真正切换横/竖屏。
/// 键盘、输入法、状态栏等全部跟随旋转。
/// 插件页面关闭时自动恢复为竖屏。
mixin OrientationMixin {
  /// JS polyfill：挂载 RainCurtain.orientation API
  static const String polyfillJS = r"""
(function() {
  if (window.__raincurtainOrientationPatched) return;
  window.__raincurtainOrientationPatched = true;

  function _call(action, data) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler('raincurtain_orientation',
      Object.assign({ action: action }, data || {}));
  }

  function mount() {
    if (!window.RainCurtain) {
      setTimeout(mount, 10);
      return;
    }
    window.RainCurtain.orientation = {
      /**
       * 锁定屏幕方向
       * @param {'landscape'|'portrait'} mode - 方向模式
       * @returns {Promise<{success: boolean, error?: string}>}
       */
      lock: function(mode) {
        if (mode !== 'landscape' && mode !== 'portrait') {
          return Promise.resolve({ success: false, error: "mode must be 'landscape' or 'portrait'" });
        }
        return _call('lock', { mode: mode });
      },
      /**
       * 解锁屏幕方向（恢复为竖屏）
       * @returns {Promise<{success: boolean}>}
       */
      unlock: function() {
        return _call('unlock');
      },
      /**
       * 获取当前方向状态
       * @returns {Promise<{mode: 'landscape'|'portrait', locked: boolean}>}
       */
      get: function() {
        return _call('get');
      }
    };
  }
  mount();
})();
""";

  /// 当前是否被插件锁定了方向
  bool _orientationLocked = false;

  /// 注册方向控制 Handler
  void registerOrientationHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'raincurtain_orientation',
      callback: (args) async {
        if (args.isEmpty) return {'success': false, 'error': 'No arguments'};
        final data = args[0] as Map<dynamic, dynamic>;
        final action = data['action'] as String? ?? '';

        switch (action) {
          case 'lock':
            return await _handleLock(data['mode'] as String?);
          case 'unlock':
            return await _handleUnlock();
          case 'get':
            return _handleGet();
          default:
            return {'success': false, 'error': 'Unknown action: $action'};
        }
      },
    );
  }

  Future<Map<String, dynamic>> _handleLock(String? mode) async {
    if (mode == null) {
      return {'success': false, 'error': 'mode is required'};
    }

    try {
      switch (mode) {
        case 'landscape':
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          _orientationLocked = true;
          return {'success': true};
        case 'portrait':
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          _orientationLocked = true;
          return {'success': true};
        default:
          return {
            'success': false,
            'error': "Invalid mode: $mode. Use 'landscape' or 'portrait'",
          };
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _handleUnlock() async {
    try {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      _orientationLocked = false;
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, dynamic> _handleGet() {
    return {
      'mode': _orientationLocked ? 'landscape' : 'portrait',
      'locked': _orientationLocked,
    };
  }

  /// 插件关闭时恢复方向为自由旋转
  void disposeOrientation() {
    if (_orientationLocked) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      _orientationLocked = false;
    }
  }
}
