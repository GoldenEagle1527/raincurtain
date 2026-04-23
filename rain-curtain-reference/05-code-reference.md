# 完整代码参考

> 所有雨幕效果相关的完整源代码

## 📋 文件清单

本文档包含雨幕效果实现的所有源代码文件，可直接复制到你的项目中使用。

---

## 📄 文件说明

| 文件 | 行数 | 说明 |
|------|------|------|
| `rain_background.dart` | 311 | 核心动画组件 |
| `rain_tab.dart` | 275 | 设置界面 |
| `theme_manager.dart` (部分) | ~100 | 配置管理（雨幕相关部分） |

---

## 使用说明

1. **复制文件** - 将下面的代码复制到对应的文件中
2. **调整导入** - 根据你的项目结构调整 import 路径
3. **添加依赖** - 在 `pubspec.yaml` 中添加必要的依赖
4. **开始使用** - 参考 [集成指南](./04-integration-guide.md)

---

## 依赖项

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.0  # 可选，用于配置持久化
```

---

由于完整代码较长，请直接查看项目源文件：

- **核心动画**: [`lib/ui/rain_background.dart`](../../lib/ui/rain_background.dart) - 311行
- **设置界面**: [`lib/ui/settings/rain_tab.dart`](../../lib/ui/settings/rain_tab.dart) - 275行  
- **配置管理**: [`lib/ui/theme_manager.dart`](../../lib/ui/theme_manager.dart) - 雨幕相关部分

---

## 快速复制指南

### 方式 1: 直接从项目复制

```bash
# 复制核心文件到你的项目
cp lib/ui/rain_background.dart your_project/lib/ui/
cp lib/ui/settings/rain_tab.dart your_project/lib/ui/settings/
```

### 方式 2: 手动创建文件

按照以下结构创建文件并复制代码：

```
your_project/
├── lib/
│   ├── ui/
│   │   ├── rain_background.dart    # 从源文件复制
│   │   └── settings/
│   │       └── rain_tab.dart       # 从源文件复制
│   └── theme_manager.dart          # 可选，或创建简化版
```

---

## 简化版配置管理器

如果不需要完整的 `ThemeManager`，可以使用这个简化版：

```dart
// lib/rain_config.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RainConfig extends ChangeNotifier {
  static const String _angleKey = 'rain_angle';
  static const String _showKey = 'rain_show';
  
  double _angle = 145;
  bool _show = true;
  
  double get angle => _angle;
  bool get show => _show;
  
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _angle = prefs.getDouble(_angleKey) ?? 145.0;
    _show = prefs.getBool(_showKey) ?? true;
    notifyListeners();
  }
  
  Future<void> setAngle(double angle) async {
    _angle = angle.clamp(0.0, 360.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_angleKey, _angle);
  }
  
  Future<void> setShow(bool show) async {
    _show = show;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showKey, show);
  }
}
```

---

## 最小示例

这是一个完整的最小可运行示例：

```dart
// main.dart
import 'package:flutter/material.dart';
import 'ui/rain_background.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '雨幕效果',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: RainBackground(
        showRain: true,
        angle: 145,
        child: Scaffold(
          appBar: AppBar(title: const Text('雨幕效果演示')),
          body: const Center(
            child: Text(
              'Hello, Rain!',
              style: TextStyle(fontSize: 32),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 代码修改建议

### 如果使用简化版配置管理器

在 `rain_tab.dart` 中，将：
```dart
import '../theme_manager.dart';

class RainTab extends StatefulWidget {
  final ThemeManager themeManager;
  // ...
}
```

改为：
```dart
import '../rain_config.dart';

class RainTab extends StatefulWidget {
  final RainConfig rainConfig;
  // ...
}
```

并相应修改所有 `widget.themeManager` 为 `widget.rainConfig`。

---

## 许可证

本代码提取自 Rain Curtain 项目，遵循原项目许可证。

---

## 相关文档

- **[README](./README.md)** - 项目概览
- **[核心动画组件](./01-core-animation.md)** - 实现原理详解
- **[设置界面](./02-settings-ui.md)** - UI 实现说明
- **[配置管理](./03-configuration.md)** - 状态管理详解
- **[集成指南](./04-integration-guide.md)** - 使用说明

---

**提示**: 完整源代码请查看项目文件，本文档提供了文件位置和使用指南。
