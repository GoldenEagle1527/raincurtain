import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'color_profile.dart';
import 'color_schemes.dart';

/// 主题状态管理
/// 管理应用的主题模式,支持亮色、暗色和跟随系统三种模式
/// 管理应用的主题颜色配置文件，提供预设颜色的选择和持久化
class ThemeProvider extends ChangeNotifier {
  // 主题模式
  ThemeMode _themeMode = ThemeMode.system;
  
  // 主题颜色配置
  AppColorProfile _colorProfile = kBuiltinProfiles.first;
  
  // 雨幕配置
  double _rainAngle = 145;
  bool _showRain = true;
  
  // SharedPreferences 的 keys
  static const String _themeModeKey = 'theme_mode';
  static const String _colorProfileKey = 'color_profile_id';
  static const String _rainAngleKey = 'rain_angle';
  static const String _showRainKey = 'show_rain';
  
  // 是否已初始化
  bool _isInitialized = false;
  
  ThemeProvider() {
    _init();
  }
  
  /// 初始化: 从 SharedPreferences 加载主题设置
  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载主题模式
      final themeModeString = prefs.getString(_themeModeKey);
      if (themeModeString != null) {
        _themeMode = _stringToThemeMode(themeModeString);
      }
      
      // 加载颜色配置
      final colorProfileId = prefs.getString(_colorProfileKey);
      if (colorProfileId != null) {
        final profile = kBuiltinProfiles.firstWhere(
            (p) => p.id == colorProfileId,
            orElse: () => kBuiltinProfiles.first,
        );
        _colorProfile = profile;
      }
      
      // 加载雨幕配置
      _rainAngle = prefs.getDouble(_rainAngleKey) ?? 145.0;
      _showRain = prefs.getBool(_showRainKey) ?? true;
      
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      // 如果加载失败,使用默认值
      _themeMode = ThemeMode.system;
      _colorProfile = kBuiltinProfiles.first;
      _rainAngle = 145.0;
      _showRain = true;
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  /// 获取当前主题模式
  ThemeMode get themeMode => _themeMode;
  
  /// 获取当前颜色配置
  AppColorProfile get colorProfile => _colorProfile;
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 获取雨幕角度
  double get rainAngle => _rainAngle;
  
  /// 获取雨幕显示状态
  bool get showRain => _showRain;
  
  /// 动态获取 Light ThemeData
  ThemeData get lightTheme {
      final scheme = AppColorSchemes.fromSeed(_colorProfile.seed, Brightness.light);
      return AppTheme.buildTheme(scheme);
  }
  
  /// 动态获取 Dark ThemeData
  ThemeData get darkTheme {
      final scheme = AppColorSchemes.fromSeed(_colorProfile.seed, Brightness.dark);
      return AppTheme.buildTheme(scheme);
  }

  /// 判断当前是否为暗色模式
  /// 如果是跟随系统模式,则根据系统亮度判断
  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // 获取系统亮度
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }
  
  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    await _saveThemeMode(mode);
    notifyListeners();
  }
  
  /// 设置颜色配置
  Future<void> setColorProfile(AppColorProfile profile) async {
      if (_colorProfile.id == profile.id) return;
      
      _colorProfile = profile;
      await _saveColorProfile(profile);
      notifyListeners();
  }

  /// 切换主题模式 (亮色 <-> 暗色)
  Future<void> toggleThemeMode() async {
    final newMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }
  
  /// 持久化保存主题模式设置
  Future<void> _saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, _themeModeToString(mode));
    } catch (e) {
      // 保存失败不影响功能
      debugPrint('Failed to save theme mode: $e');
    }
  }

  /// 持久化保存主题颜色设置
  Future<void> _saveColorProfile(AppColorProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_colorProfileKey, profile.id);
    } catch (e) {
      // 保存失败不影响功能
      debugPrint('Failed to save color profile: $e');
    }
  }
  
  /// 将 ThemeMode 转换为字符串
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
  
  /// 将字符串转换为 ThemeMode
  ThemeMode _stringToThemeMode(String string) {
    switch (string) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }
  
  /// 获取主题模式的显示名称
  String getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '亮色模式';
      case ThemeMode.dark:
        return '暗色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
  
  /// 获取主题模式的图标
  IconData getThemeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }
  
  /// 设置雨幕角度
  Future<void> setRainAngle(double angle) async {
    final normalizedAngle = angle.clamp(-360.0, 360.0);
    if (_rainAngle == normalizedAngle) return;
    
    _rainAngle = normalizedAngle;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rainAngleKey, normalizedAngle);
  }
  
  /// 设置雨幕显示状态
  Future<void> setShowRain(bool show) async {
    if (_showRain == show) return;
    
    _showRain = show;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRainKey, show);
  }
}
