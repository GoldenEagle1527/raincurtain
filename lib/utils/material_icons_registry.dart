import 'package:flutter/services.dart' show rootBundle;
import '../models/plugin_icon.dart';

/// Material Icons 名称 -> Unicode 码点 注册表
///
/// 通过加载 Google 官方 codepoints 文件，支持全部约 2000 个图标。
/// 不再使用硬编码白名单。
///
/// 由于 Flutter release 构建默认开启 icon tree-shaking
/// （只打包以字面量 `IconData(0xeXXX)` 出现的码点），
/// 本项目通过 [Text] + 字体族直接渲染字符，**绕开** tree-shaker，
/// 无需在构建时添加 `--no-tree-shake-icons`。
class MaterialIconsRegistry {
  MaterialIconsRegistry._();
  static final MaterialIconsRegistry instance = MaterialIconsRegistry._();

  /// 已加载完成的 variant 名称 -> (iconName -> codePoint) 映射
  final Map<MaterialIconVariant, Map<String, int>> _maps = {};

  /// 各 variant 对应的 codepoints asset 路径
  static const Map<MaterialIconVariant, String> _assetPaths = {
    MaterialIconVariant.filled:
        'assets/fonts/material-icons/MaterialIcons-Regular.codepoints',
    MaterialIconVariant.outlined:
        'assets/fonts/material-icons/MaterialIconsOutlined-Regular.codepoints',
    MaterialIconVariant.rounded:
        'assets/fonts/material-icons/MaterialIconsRound-Regular.codepoints',
    MaterialIconVariant.sharp:
        'assets/fonts/material-icons/MaterialIconsSharp-Regular.codepoints',
    MaterialIconVariant.twoTone:
        'assets/fonts/material-icons/MaterialIconsTwoTone-Regular.codepoints',
  };

  /// variant 对应的字体族名（与 pubspec.yaml 中 family 字段一致）
  static const Map<MaterialIconVariant, String> _fontFamilies = {
    MaterialIconVariant.filled: 'MaterialIconsFilled',
    MaterialIconVariant.outlined: 'MaterialIconsOutlined',
    MaterialIconVariant.rounded: 'MaterialIconsRounded',
    MaterialIconVariant.sharp: 'MaterialIconsSharp',
    MaterialIconVariant.twoTone: 'MaterialIconsTwoTone',
  };

  bool _initialized = false;
  Future<void>? _initFuture;

  /// 预加载全部 codepoints（应用启动时调用一次）
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initFuture ??= _loadAll();
  }

  Future<void> _loadAll() async {
    for (final entry in _assetPaths.entries) {
      try {
        final raw = await rootBundle.loadString(entry.value);
        _maps[entry.key] = _parse(raw);
      } catch (_) {
        // 缺失某个 variant 时静默降级，调用方会自动回退到 filled
        _maps[entry.key] = const {};
      }
    }
    _initialized = true;
  }

  /// 解析 Google codepoints 文件：每行 `name hex`
  Map<String, int> _parse(String content) {
    final result = <String, int>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final spaceIdx = trimmed.indexOf(' ');
      if (spaceIdx <= 0) continue;
      final name = trimmed.substring(0, spaceIdx);
      final hex = trimmed.substring(spaceIdx + 1).trim();
      final cp = int.tryParse(hex, radix: 16);
      if (cp != null) result[name] = cp;
    }
    return result;
  }

  /// 查询图标码点。未命中指定 variant 时回退到 filled。
  /// 返回 null 表示该名称在 Material Icons 中不存在。
  int? lookup(String iconName, MaterialIconVariant variant) {
    final primary = _maps[variant];
    final cp = primary?[iconName];
    if (cp != null) return cp;
    if (variant != MaterialIconVariant.filled) {
      return _maps[MaterialIconVariant.filled]?[iconName];
    }
    return null;
  }

  /// 根据 variant 取字体族名（已确认存在则返回该 variant，否则回退 filled）
  String fontFamilyFor(String iconName, MaterialIconVariant variant) {
    final primary = _maps[variant];
    if (primary != null && primary.containsKey(iconName)) {
      return _fontFamilies[variant]!;
    }
    return _fontFamilies[MaterialIconVariant.filled]!;
  }

  /// 是否已完成初始化
  bool get isReady => _initialized;
}
