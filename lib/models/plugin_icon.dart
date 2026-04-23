/// 插件图标类型
sealed class PluginIcon {
  const PluginIcon();

  /// 默认图标
  static const PluginIcon defaultIcon = DefaultIcon();

  /// 从字符串解析图标
  factory PluginIcon.parse(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const DefaultIcon();
    }

    final trimmed = value.trim();

    // 检查是否为 Material Icons
    if (trimmed.startsWith('material:')) {
      return _parseMaterialIcon(trimmed);
    }

    // 判断是否为图片路径
    if (_isImagePath(trimmed)) {
      return PluginImageIcon(trimmed);
    }

    // 不再支持 Unicode/Emoji,无效格式使用默认图标
    return const DefaultIcon();
  }

  /// 解析 Material Icons 格式: material:icon_name[:variant]
  static PluginIcon _parseMaterialIcon(String value) {
    // 移除 "material:" 前缀
    final parts = value.substring(9).split(':');
    if (parts.isEmpty || parts[0].isEmpty) {
      return const DefaultIcon();
    }

    final iconName = parts[0];

    MaterialIconVariant variant = MaterialIconVariant.filled;
    if (parts.length > 1) {
      variant = switch (parts[1].toLowerCase()) {
        'outlined' => MaterialIconVariant.outlined,
        'rounded' => MaterialIconVariant.rounded,
        'sharp' => MaterialIconVariant.sharp,
        'two-tone' || 'twotone' => MaterialIconVariant.twoTone,
        _ => MaterialIconVariant.filled,
      };
    }

    return MaterialIcon(iconName, variant: variant);
  }

  static bool _isImagePath(String value) {
    // 以 ./ 开头，或包含路径分隔符，或以图片扩展名结尾
    final imageExtensions = [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.wbmp',
      '.svg',
    ];
    final lowerValue = value.toLowerCase();

    if (value.startsWith('./') || value.contains('/')) {
      return true;
    }

    return imageExtensions.any((ext) => lowerValue.endsWith(ext));
  }
}

/// 默认图标
class DefaultIcon extends PluginIcon {
  const DefaultIcon();
}

/// Material Icons 字体图标
class MaterialIcon extends PluginIcon {
  const MaterialIcon(
    this.iconName, {
    this.variant = MaterialIconVariant.filled,
  });

  final String iconName;
  final MaterialIconVariant variant;
}

/// Material Icons 样式变体
enum MaterialIconVariant {
  filled,   // 默认填充样式
  outlined, // 轮廓样式
  rounded,  // 圆角样式
  sharp,    // 锐角样式
  twoTone,  // 双色样式
}

/// 图片路径图标
class PluginImageIcon extends PluginIcon {
  const PluginImageIcon(this.relativePath);

  final String relativePath;
}
