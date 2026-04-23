# 雨幕(遮罩层)实现参考文档

> 从 Rain Curtain 项目提取的雨幕动画系统完整实现参考

## 📖 简介

本参考文档提供了一个完整的、可复用的雨幕动画效果实现，包括：

- 🎨 **高性能动画** - 使用 Flutter CustomPainter 实现的流畅雨滴效果
- ⚙️ **灵活配置** - 支持角度、数量、颜色、透明度等多维度调整
- 🎛️ **完整 UI** - 包含设置界面和交互式方向选择器
- 💾 **状态管理** - 配置持久化和主题集成方案
- 📱 **生产就绪** - 已在实际项目中验证的稳定实现

## 🎯 效果展示

雨幕效果特点：
- 水滴形状的雨滴（圆头尖尾）
- 带渐变拖尾效果
- 支持任意角度（0-360度）
- 颜色自动跟随主题
- 透明度淡入淡出
- 无限循环动画

## 📚 文档结构

1. **[核心动画组件](./01-core-animation.md)** - `RainBackground` 和 `_RainPainter` 实现详解
2. **[设置界面](./02-settings-ui.md)** - `RainTab` 和方向选择器实现
3. **[配置管理](./03-configuration.md)** - 状态管理和持久化方案
4. **[集成指南](./04-integration-guide.md)** - 如何在项目中使用
5. **[完整代码](./05-code-reference.md)** - 所有源代码文件

## 🚀 快速开始

### 基础用法

```dart
import 'package:flutter/material.dart';
import 'rain_background.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: RainBackground(
        showRain: true,
        angle: 145,
        child: Scaffold(
          appBar: AppBar(title: Text('雨幕效果')),
          body: Center(child: Text('Hello, Rain!')),
        ),
      ),
    );
  }
}
```

### 高级配置

```dart
RainBackground(
  showRain: true,           // 是否显示雨滴
  angle: 145,               // 雨滴角度（0-360度）
  dropCount: 80,            // 雨滴数量
  opacity: 0.25,            // 不透明度
  rainColor: Colors.blue,   // 自定义颜色（null则跟随主题）
  child: YourWidget(),
)
```

## 📦 文件清单

### 核心文件
- `rain_background.dart` - 雨幕动画核心组件（311行）
- `rain_tab.dart` - 设置界面实现（275行）
- `theme_manager.dart` - 配置管理（部分代码）

### 依赖项
```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.0.0  # 可选，用于配置持久化
```

## 🎨 技术特点

### 性能优化
- ✅ 使用 `Ticker` 驱动动画，性能优于 `AnimationController`
- ✅ `CustomPainter` 直接绘制，避免 Widget 重建
- ✅ `IgnorePointer` 确保不拦截触摸事件
- ✅ 精确的 `shouldRepaint` 控制

### 数学算法
- 角度转换和弧度计算
- 循环动画时间插值
- 透明度渐变函数
- 基于对角线的位置计算

### 视觉设计
- 水滴形状：贝塞尔曲线绘制
- 拖尾效果：8段渐变线条
- 主题适配：自动跟随 Material Design 3 主题色
- 深浅色模式支持

## 🔧 可配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `showRain` | `bool` | `true` | 是否显示雨滴动画 |
| `angle` | `double` | `145` | 雨滴下落角度（0-360度） |
| `dropCount` | `int` | `80` | 雨滴数量（建议 50-100） |
| `opacity` | `double` | `0.25` | 雨滴不透明度（0.0-1.0） |
| `rainColor` | `Color?` | `null` | 雨滴颜色（null则跟随主题） |
| `child` | `Widget` | 必需 | 子组件 |

## 💡 使用建议

### 适用场景
- ✅ 应用全局背景装饰
- ✅ 特定页面氛围营造
- ✅ 主题切换视觉反馈
- ✅ 加载等待界面美化

### 性能建议
- 雨滴数量建议不超过 100 个
- 在低端设备上提供关闭选项
- 避免在频繁滚动的列表中使用
- 可根据设备性能动态调整参数

### 主题适配
- 深色模式下可能需要调整透明度
- 确保雨滴颜色与背景有足够对比度
- 建议使用主题色以保持一致性

## 📖 详细文档

- **[01-核心动画组件](./01-core-animation.md)** - 深入了解 `RainBackground`、`_RainDrop` 和 `_RainPainter` 的实现原理
- **[02-设置界面](./02-settings-ui.md)** - 学习如何构建雨幕设置界面和交互式方向选择器
- **[03-配置管理](./03-configuration.md)** - 了解状态管理和持久化存储方案
- **[04-集成指南](./04-integration-guide.md)** - 获取完整的集成步骤和最佳实践
- **[05-完整代码](./05-code-reference.md)** - 查看所有源代码文件

## 🤝 贡献

本参考文档提取自 [Rain Curtain](https://github.com/your-repo/rain_curtain) 项目。

## 📄 许可证

本参考文档遵循原项目的许可证。

## 🔗 相关资源

- [Flutter CustomPainter 文档](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)
- [Flutter Animation 指南](https://docs.flutter.dev/development/ui/animations)
- [Material Design 3](https://m3.material.io/)

---

**最后更新**: 2026-04-23  
**来源项目**: Rain Curtain  
**提取目的**: 为其他 Flutter 项目提供雨幕效果实现参考
