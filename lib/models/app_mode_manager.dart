import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode {
  rain, // 雨幕模式
  stream, // 溯流模式
}

class AppModeManager extends ChangeNotifier {
  AppMode _currentMode = AppMode.rain;
  bool _isInit = false;

  AppMode get currentMode => _currentMode;
  bool get isInit => _isInit;
  bool get isRainMode => _currentMode == AppMode.rain;
  bool get isStreamMode => _currentMode == AppMode.stream;

  AppModeManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString('app_mode');
      if (modeStr != null) {
        _currentMode = AppMode.values.firstWhere(
          (m) => m.name == modeStr,
          orElse: () => AppMode.rain,
        );
      }
    } catch (e) {
      debugPrint('Failed to load app mode: $e');
    } finally {
      _isInit = true;
      notifyListeners();
    }
  }

  Future<void> switchMode() async {
    _currentMode =
        _currentMode == AppMode.rain ? AppMode.stream : AppMode.rain;
    await _saveMode();
    notifyListeners();
  }

  Future<void> setMode(AppMode mode) async {
    if (_currentMode != mode) {
      _currentMode = mode;
      await _saveMode();
      notifyListeners();
    }
  }

  Future<void> _saveMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_mode', _currentMode.name);
    } catch (e) {
      debugPrint('Failed to save app mode: $e');
    }
  }
}
