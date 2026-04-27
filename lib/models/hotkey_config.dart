// ignore_for_file: constant_identifier_names

import 'package:shared_preferences/shared_preferences.dart';

class HotkeyConfig {
  final bool enabled;
  final int modifiers;
  final int keyCode;

  // 修饰键常量 (Windows MOD_* 值)
  static const int MOD_ALT = 0x0001;
  static const int MOD_CONTROL = 0x0002;
  static const int MOD_SHIFT = 0x0004;
  static const int MOD_WIN = 0x0008;

  const HotkeyConfig({
    this.enabled = false,
    this.modifiers = 0,
    this.keyCode = 0,
  });

  // 从SharedPreferences加载
  factory HotkeyConfig.fromPrefs(SharedPreferences prefs) {
    return HotkeyConfig(
      enabled: prefs.getBool('hotkey_enabled') ?? false,
      modifiers: prefs.getInt('hotkey_modifiers') ?? 0,
      keyCode: prefs.getInt('hotkey_keycode') ?? 0,
    );
  }

  // 保存到SharedPreferences
  Future<void> saveToPrefs(SharedPreferences prefs) async {
    await prefs.setBool('hotkey_enabled', enabled);
    await prefs.setInt('hotkey_modifiers', modifiers);
    await prefs.setInt('hotkey_keycode', keyCode);
  }

  // 生成快捷键描述文本
  String get description {
    if (!enabled || keyCode == 0) return '未设置';

    List<String> parts = [];
    if (modifiers & MOD_CONTROL != 0) parts.add('Ctrl');
    if (modifiers & MOD_ALT != 0) parts.add('Alt');
    if (modifiers & MOD_SHIFT != 0) parts.add('Shift');
    if (modifiers & MOD_WIN != 0) parts.add('Win');

    // 将虚拟键码转换为可读字符
    parts.add(_keyCodeToString(keyCode));

    return parts.join(' + ');
  }

  String _keyCodeToString(int code) {
    // VK_A-Z: 0x41-0x5A
    if (code >= 0x41 && code <= 0x5A) {
      return String.fromCharCode(code);
    }
    // VK_0-9: 0x30-0x39
    if (code >= 0x30 && code <= 0x39) {
      return String.fromCharCode(code);
    }
    // F1-F12: 0x70-0x7B
    if (code >= 0x70 && code <= 0x7B) {
      return 'F${code - 0x6F}';
    }
    // 特殊键
    switch (code) {
      case 0x20:
        return 'Space';
      case 0x0D:
        return 'Enter';
      case 0x1B:
        return 'Esc';
      case 0x09:
        return 'Tab';
      default:
        return 'Key${code.toRadixString(16).toUpperCase()}';
    }
  }

  HotkeyConfig copyWith({bool? enabled, int? modifiers, int? keyCode}) {
    return HotkeyConfig(
      enabled: enabled ?? this.enabled,
      modifiers: modifiers ?? this.modifiers,
      keyCode: keyCode ?? this.keyCode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HotkeyConfig &&
        other.enabled == enabled &&
        other.modifiers == modifiers &&
        other.keyCode == keyCode;
  }

  @override
  int get hashCode => Object.hash(enabled, modifiers, keyCode);
}
