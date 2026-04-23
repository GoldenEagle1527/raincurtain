import 'package:flutter/material.dart';

/// MD3 颜色方案定义
class AppColorSchemes {
  // 私有构造函数,防止实例化
  AppColorSchemes._();

  /// 动态生成颜色方案
  static ColorScheme fromSeed(Color seed, Brightness brightness) {
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
  }
}
