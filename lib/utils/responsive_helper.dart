import 'package:flutter/material.dart';

/// 屏幕尺寸类型
/// 基于 Material Design 3 的响应式布局断点
enum ScreenSize {
  /// 紧凑型: < 600dp (手机竖屏)
  compact,
  /// 中等型: 600-840dp (手机横屏/小平板)
  medium,
  /// 扩展型: 840-1200dp (平板/小桌面)
  expanded,
  /// 大型: 1200-1600dp (桌面)
  large,
  /// 超大型: > 1600dp (大屏桌面)
  extraLarge,
}

/// 响应式布局辅助工具
/// 提供屏幕尺寸判断和响应式参数计算
class ResponsiveHelper {
  // 私有构造函数,防止实例化
  ResponsiveHelper._();
  
  /// 断点定义
  static const double compactBreakpoint = 600;
  static const double mediumBreakpoint = 840;
  static const double expandedBreakpoint = 1200;
  static const double largeBreakpoint = 1600;
  
  /// 获取当前屏幕尺寸类型
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < compactBreakpoint) return ScreenSize.compact;
    if (width < mediumBreakpoint) return ScreenSize.medium;
    if (width < expandedBreakpoint) return ScreenSize.expanded;
    if (width < largeBreakpoint) return ScreenSize.large;
    return ScreenSize.extraLarge;
  }
  
  /// 获取屏幕宽度
  static double getScreenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }
  
  /// 获取屏幕高度
  static double getScreenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
  
  /// 判断是否为紧凑型屏幕
  static bool isCompact(BuildContext context) {
    return getScreenSize(context) == ScreenSize.compact;
  }
  
  /// 判断是否为中等或更大屏幕
  static bool isMediumOrLarger(BuildContext context) {
    final size = getScreenSize(context);
    return size != ScreenSize.compact;
  }
  
  /// 判断是否为扩展或更大屏幕
  static bool isExpandedOrLarger(BuildContext context) {
    final size = getScreenSize(context);
    return size == ScreenSize.expanded ||
           size == ScreenSize.large ||
           size == ScreenSize.extraLarge;
  }
  
  /// 判断是否为大型或更大屏幕
  static bool isLargeOrLarger(BuildContext context) {
    final size = getScreenSize(context);
    return size == ScreenSize.large || size == ScreenSize.extraLarge;
  }
  
  /// 判断是否为超大型屏幕
  static bool isExtraLarge(BuildContext context) {
    return getScreenSize(context) == ScreenSize.extraLarge;
  }
  
  /// 获取内容区域内边距
  /// 根据屏幕尺寸返回合适的内边距值
  static double getContentPadding(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 16.0;
      case ScreenSize.medium:
        return 24.0;
      case ScreenSize.expanded:
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 32.0;
    }
  }
  
  /// 获取卡片内边距
  static double getCardPadding(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 16.0;
      case ScreenSize.medium:
        return 20.0;
      case ScreenSize.expanded:
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 24.0;
    }
  }
  
  /// 获取网格交叉轴数量 (列数)
  static int getGridCrossAxisCount(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 1;
      case ScreenSize.medium:
        return 2;
      case ScreenSize.expanded:
        return 3;
      case ScreenSize.large:
        return 4;
      case ScreenSize.extraLarge:
        return 5;
    }
  }
  
  /// 获取网格主轴间距
  static double getGridMainAxisSpacing(BuildContext context) {
    return 16.0;
  }
  
  /// 获取网格交叉轴间距
  static double getGridCrossAxisSpacing(BuildContext context) {
    return 16.0;
  }
  
  /// 获取列表项间距
  static double getListItemSpacing(BuildContext context) {
    return 12.0;
  }
  
  /// 获取导航栏宽度 (NavigationRail)
  static double getNavigationRailWidth(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 0.0; // 紧凑型不使用 NavigationRail
      case ScreenSize.medium:
        return 72.0; // 仅图标
      case ScreenSize.expanded:
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 88.0; // 图标 + 文字
    }
  }
  
  /// 获取最大内容宽度
  /// 用于限制超宽屏幕上的内容宽度,提高可读性
  static double getMaxContentWidth(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
      case ScreenSize.medium:
        return double.infinity; // 不限制
      case ScreenSize.expanded:
        return 1200.0;
      case ScreenSize.large:
        return 1400.0;
      case ScreenSize.extraLarge:
        return 1600.0;
    }
  }
  
  /// 判断是否应该使用抽屉导航 (Drawer)
  static bool shouldUseDrawer(BuildContext context) {
    return isCompact(context);
  }
  
  /// 判断是否应该使用侧边导航栏 (NavigationRail)
  static bool shouldUseNavigationRail(BuildContext context) {
    final size = getScreenSize(context);
    return size == ScreenSize.medium || size == ScreenSize.expanded;
  }
  
  /// 判断是否应该使用顶部标签栏
  static bool shouldUseTopTabBar(BuildContext context) {
    return isLargeOrLarger(context);
  }
  
  /// 获取按钮高度
  static double getButtonHeight(BuildContext context) {
    return 40.0;
  }
  
  /// 获取图标大小
  static double getIconSize(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 24.0;
      case ScreenSize.medium:
      case ScreenSize.expanded:
        return 24.0;
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 24.0;
    }
  }
  
  /// 获取标题字体大小
  static double getTitleFontSize(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 20.0;
      case ScreenSize.medium:
      case ScreenSize.expanded:
        return 22.0;
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 24.0;
    }
  }
  
  /// 获取正文字体大小
  static double getBodyFontSize(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 14.0;
      case ScreenSize.medium:
      case ScreenSize.expanded:
        return 15.0;
      case ScreenSize.large:
      case ScreenSize.extraLarge:
        return 16.0;
    }
  }
  
  /// 根据屏幕尺寸返回不同的值
  static T responsive<T>(
    BuildContext context, {
    required T compact,
    T? medium,
    T? expanded,
    T? large,
    T? extraLarge,
  }) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return compact;
      case ScreenSize.medium:
        return medium ?? compact;
      case ScreenSize.expanded:
        return expanded ?? medium ?? compact;
      case ScreenSize.large:
        return large ?? expanded ?? medium ?? compact;
      case ScreenSize.extraLarge:
        return extraLarge ?? large ?? expanded ?? medium ?? compact;
    }
  }
}
