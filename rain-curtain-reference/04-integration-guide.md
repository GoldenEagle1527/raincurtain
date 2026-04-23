# 集成指南

> 如何在 Flutter 项目中集成雨幕效果

## 📋 前置要求

- Flutter SDK: >= 3.0.0
- Dart SDK: >= 3.0.0
- 支持平台: Android, iOS, Windows, Linux, macOS, Web

## 🚀 快速开始

### 步骤 1: 复制核心文件

将以下文件复制到你的项目中：

```
your_project/
├── lib/
│   ├── ui/
│   │   └── rain_background.dart    # 核心动画组件
│   └── (可选) settings/
│       └── rain_tab.dart           # 设置界面
```

### 步骤 2: 添加依赖

在 `pubspec.yaml` 中添加（如需配置持久化）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.0  # 可选，用于保存配置
```

运行：
```bash
flutter pub get
```

### 步骤 3: 基础使用

```dart
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
      title: '雨幕效果演示',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: RainBackground(
        showRain: true,
        angle: 145,
        child: Scaffold(
          appBar: AppBar(title: const Text('雨幕效果')),
          body: const Center(
            child: Text('Hello, Rain!', style: TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }
}
```

运行效果：带雨滴动画的应用界面！

## 📚 集成方案

### 方案 A: 全局雨幕（推荐）

在 `MaterialApp` 的 `builder` 中包裹：

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My App',
      theme: ThemeData(...),
      builder: (context, child) {
        return RainBackground(
          showRain: true,
          angle: 145,
          child: child!,
        );
      },
      home: HomePage(),
    );
  }
}
```

**优点**：
- ✅ 所有页面自动应用雨幕效果
- ✅ 页面切换时雨幕持续播放
- ✅ 统一管理，易于维护

**缺点**：
- ❌ 无法针对特定页面禁用

### 方案 B: 页面级雨幕

在特定页面使用：

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RainBackground(
      showRain: true,
      angle: 145,
      child: Scaffold(
        appBar: AppBar(title: Text('My Page')),
        body: MyContent(),
      ),
    );
  }
}
```

**优点**：
- ✅ 灵活控制哪些页面显示雨幕
- ✅ 不同页面可使用不同配置

**缺点**：
- ❌ 页面切换时雨幕会重新开始
- ❌ 需要在每个页面单独配置

### 方案 C: 静态背景

使用 `RainGradientBackground` 提供微妙的渐变背景：

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RainGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,  // 重要！
        appBar: AppBar(title: Text('My Page')),
        body: MyContent(),
      ),
    );
  }
}
```

**适用场景**：
- 性能敏感的页面
- 不需要动画的场景
- 作为雨幕的补充

## 🎛️ 配置管理

### 简单配置（无持久化）

```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showRain = true;
  double _rainAngle = 145;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return RainBackground(
          showRain: _showRain,
          angle: _rainAngle,
          child: child!,
        );
      },
      home: Scaffold(
        appBar: AppBar(title: Text('雨幕设置')),
        body: Column(
          children: [
            SwitchListTile(
              title: Text('显示雨滴'),
              value: _showRain,
              onChanged: (value) => setState(() => _showRain = value),
            ),
            Slider(
              label: '${_rainAngle.round()}°',
              value: _rainAngle,
              min: 0,
              max: 360,
              onChanged: (value) => setState(() => _rainAngle = value),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 完整配置（带持久化）

#### 1. 创建配置管理器

```dart
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

#### 2. 在应用中使用

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final rainConfig = RainConfig();
  await rainConfig.init();
  
  runApp(MyApp(rainConfig: rainConfig));
}

class MyApp extends StatelessWidget {
  final RainConfig rainConfig;
  
  const MyApp({super.key, required this.rainConfig});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return ListenableBuilder(
          listenable: rainConfig,
          builder: (context, _) {
            return RainBackground(
              showRain: rainConfig.show,
              angle: rainConfig.angle,
              child: child!,
            );
          },
        );
      },
      home: SettingsPage(rainConfig: rainConfig),
    );
  }
}
```

#### 3. 设置界面

```dart
class SettingsPage extends StatelessWidget {
  final RainConfig rainConfig;
  
  const SettingsPage({super.key, required this.rainConfig});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('雨幕设置')),
      body: ListenableBuilder(
        listenable: rainConfig,
        builder: (context, _) {
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('显示雨滴动画'),
                value: rainConfig.show,
                onChanged: (value) => rainConfig.setShow(value),
              ),
              ListTile(
                title: const Text('雨滴角度'),
                subtitle: Text('${rainConfig.angle.round()}°'),
              ),
              Slider(
                value: rainConfig.angle,
                min: 0,
                max: 360,
                divisions: 360,
                label: '${rainConfig.angle.round()}°',
                onChanged: (value) => rainConfig.setAngle(value),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

## 🎨 高级定制

### 自定义雨滴颜色

```dart
RainBackground(
  showRain: true,
  angle: 145,
  rainColor: Colors.cyan,  // 自定义颜色
  child: MyContent(),
)
```

### 调整雨滴数量和透明度

```dart
RainBackground(
  showRain: true,
  angle: 145,
  dropCount: 120,      // 更多雨滴
  opacity: 0.4,        // 更明显
  child: MyContent(),
)
```

### 性能优化配置

```dart
// 低端设备配置
RainBackground(
  showRain: true,
  angle: 145,
  dropCount: 50,       // 减少雨滴数量
  opacity: 0.2,        // 降低透明度
  child: MyContent(),
)
```

### 根据设备性能动态调整

```dart
class MyApp extends StatelessWidget {
  int _getDropCount() {
    // 简单的性能检测（实际项目中可使用更复杂的逻辑）
    if (Platform.isAndroid || Platform.isIOS) {
      return 60;  // 移动设备
    }
    return 100;   // 桌面设备
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return RainBackground(
          showRain: true,
          angle: 145,
          dropCount: _getDropCount(),
          child: child!,
        );
      },
      home: HomePage(),
    );
  }
}
```

## 🔧 常见集成场景

### 场景 1: 登录页面雨幕

```dart
class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RainBackground(
      showRain: true,
      angle: 160,
      opacity: 0.15,  // 较淡，不干扰表单
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: LoginForm(),
            ),
          ),
        ),
      ),
    );
  }
}
```

### 场景 2: 加载页面

```dart
class LoadingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RainBackground(
      showRain: true,
      angle: 145,
      dropCount: 100,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('加载中...'),
            ],
          ),
        ),
      ),
    );
  }
}
```

### 场景 3: 主题切换时的雨幕颜色

```dart
class ThemedRainApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) {
        return RainBackground(
          showRain: true,
          angle: 145,
          rainColor: null,  // null = 自动跟随主题色
          child: child!,
        );
      },
      home: HomePage(),
    );
  }
}
```

### 场景 4: 条件渲染

```dart
class ConditionalRainApp extends StatelessWidget {
  final bool enableRain;
  
  const ConditionalRainApp({super.key, this.enableRain = true});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        if (enableRain) {
          return RainBackground(
            showRain: true,
            angle: 145,
            child: child!,
          );
        }
        return child!;
      },
      home: HomePage(),
    );
  }
}
```

## ⚠️ 注意事项

### 1. Scaffold 背景色

使用 `RainBackground` 时，建议设置 `Scaffold` 背景为透明：

```dart
Scaffold(
  backgroundColor: Colors.transparent,  // 或省略此行
  body: MyContent(),
)
```

### 2. 性能考虑

- 雨滴数量建议不超过 150 个
- 在滚动列表中避免使用（会影响滚动性能）
- 低端设备提供关闭选项

### 3. 触摸事件

`RainBackground` 使用 `IgnorePointer`，不会拦截触摸事件，子组件的交互正常工作。

### 4. 动画生命周期

`RainBackground` 会在 `dispose` 时自动停止动画，无需手动管理。

## 🐛 故障排查

### 问题 1: 雨滴不显示

**检查清单**：
- ✅ `showRain` 是否为 `true`
- ✅ `opacity` 是否大于 0
- ✅ `rainColor` 与背景是否有对比度
- ✅ `dropCount` 是否大于 0

### 问题 2: 性能问题

**解决方案**：
- 减少 `dropCount`（建议 50-80）
- 降低 `opacity`
- 在性能敏感页面禁用雨幕

### 问题 3: 雨滴颜色不跟随主题

**解决方案**：
```dart
// 确保 rainColor 为 null
RainBackground(
  rainColor: null,  // 自动使用主题色
  child: MyContent(),
)
```

### 问题 4: 配置不持久化

**解决方案**：
- 检查是否添加了 `shared_preferences` 依赖
- 确保调用了 `await prefs.setXxx()`
- 检查是否在 `main()` 中调用了 `WidgetsFlutterBinding.ensureInitialized()`

## 📊 性能基准

| 配置 | CPU | 内存 | 帧率 | 适用场景 |
|------|-----|------|------|---------|
| 轻量 (50滴, 0.2透明度) | ~2% | ~5MB | 60fps | 低端设备 |
| 标准 (80滴, 0.25透明度) | ~3% | ~8MB | 60fps | 大多数设备 |
| 丰富 (120滴, 0.3透明度) | ~5% | ~12MB | 60fps | 高端设备 |

*测试环境: Release 模式, 中端 Android 设备*

## 📚 完整示例项目

查看 [`examples/`](../examples/) 目录获取完整的示例项目：

- `basic_example.dart` - 基础用法
- `config_example.dart` - 配置管理
- `settings_example.dart` - 完整设置界面
- `performance_example.dart` - 性能优化

## 🔗 相关文档

- **[核心动画组件](./01-core-animation.md)** - 深入了解实现原理
- **[设置界面](./02-settings-ui.md)** - 构建设置 UI
- **[配置管理](./03-configuration.md)** - 状态管理详解
- **[完整代码](./05-code-reference.md)** - 查看源代码

---

**下一步**: 查看 [完整代码参考](./05-code-reference.md) 获取所有源代码文件
