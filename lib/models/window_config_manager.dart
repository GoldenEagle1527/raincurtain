import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hotkey_config.dart';

class WindowConfigManager extends ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('raincurtain/window_control');

  HotkeyConfig _hotkeyConfig = const HotkeyConfig();
  bool _isInitialized = false;

  HotkeyConfig get hotkeyConfig => _hotkeyConfig;
  bool get isInitialized => _isInitialized;

  // 初始化
  Future<void> init() async {
    if (!Platform.isWindows) {
      _isInitialized = true;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _hotkeyConfig = HotkeyConfig.fromPrefs(prefs);

      // 如果启用了快捷键,注册到系统
      if (_hotkeyConfig.enabled && _hotkeyConfig.keyCode != 0) {
        await _registerHotkey();
      }

      // 监听来自原生层的事件
      _channel.setMethodCallHandler(_handleMethodCall);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('初始化窗口配置失败: $e');
      _isInitialized = true;
    }
  }

  // 设置快捷键
  Future<bool> setHotkey(int modifiers, int keyCode) async {
    if (!Platform.isWindows) return false;

    try {
      // 先注销旧的快捷键
      if (_hotkeyConfig.enabled) {
        await _channel.invokeMethod('unregisterHotkey');
      }

      // 注册新快捷键
      final result = await _channel.invokeMethod('registerHotkey', {
        'modifiers': modifiers,
        'keyCode': keyCode,
      });

      if (result == true) {
        _hotkeyConfig = HotkeyConfig(
          enabled: true,
          modifiers: modifiers,
          keyCode: keyCode,
        );

        // 保存配置
        final prefs = await SharedPreferences.getInstance();
        await _hotkeyConfig.saveToPrefs(prefs);

        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('设置快捷键失败: $e');
      return false;
    }
  }

  // 禁用快捷键
  Future<void> disableHotkey() async {
    if (!Platform.isWindows) return;

    try {
      if (_hotkeyConfig.enabled) {
        await _channel.invokeMethod('unregisterHotkey');

        _hotkeyConfig = const HotkeyConfig(enabled: false);

        final prefs = await SharedPreferences.getInstance();
        await _hotkeyConfig.saveToPrefs(prefs);

        notifyListeners();
      }
    } catch (e) {
      debugPrint('禁用快捷键失败: $e');
    }
  }

  // 显示窗口
  Future<void> showWindow() async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('showWindow');
    } catch (e) {
      debugPrint('显示窗口失败: $e');
    }
  }

  // 隐藏窗口
  Future<void> hideWindow() async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('hideWindow');
    } catch (e) {
      debugPrint('隐藏窗口失败: $e');
    }
  }

  // 退出应用
  Future<void> exitApp() async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('exitApp');
    } catch (e) {
      debugPrint('退出应用失败: $e');
    }
  }

  // 处理来自原生层的调用
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onHotkeyPressed':
        // 快捷键被触发,显示窗口
        await showWindow();
        break;
    }
  }

  // 注册快捷键
  Future<void> _registerHotkey() async {
    try {
      await _channel.invokeMethod('registerHotkey', {
        'modifiers': _hotkeyConfig.modifiers,
        'keyCode': _hotkeyConfig.keyCode,
      });
    } catch (e) {
      debugPrint('注册快捷键失败: $e');
    }
  }
}
