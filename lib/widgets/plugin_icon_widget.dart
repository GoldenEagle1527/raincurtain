import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/plugin_manager.dart';
import '../models/plugin_icon.dart';
import '../utils/material_icons_registry.dart';
import '../main.dart' show sandboxServerPort;

/// 插件图标显示组件
class PluginIconWidget extends StatelessWidget {
  const PluginIconWidget({
    super.key,
    required this.plugin,
    this.size = 32.0,
  });

  final LocalPlugin plugin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = plugin.manifest.icon;

    return Container(
      width: size + 16,
      height: size + 16,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(colorScheme, icon),
        borderRadius: BorderRadius.circular(8),
      ),
      child: switch (icon) {
        DefaultIcon() => _buildDefaultIcon(colorScheme),
        MaterialIcon(:final iconName, :final variant) =>
          _buildMaterialIcon(iconName, variant, colorScheme),
        PluginImageIcon(:final relativePath) =>
          _buildImageIcon(plugin, relativePath, colorScheme),
      },
    );
  }

  Color _getBackgroundColor(ColorScheme colorScheme, PluginIcon icon) {
    return switch (icon) {
      DefaultIcon() => colorScheme.primaryContainer,
      _ => colorScheme.primaryContainer.withValues(alpha: 0.3),
    };
  }

  Widget _buildDefaultIcon(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.apps,
        size: size,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }

  /// 构建 Material Icons 图标
  Widget _buildMaterialIcon(
    String iconName,
    MaterialIconVariant variant,
    ColorScheme colorScheme,
  ) {
    final registry = MaterialIconsRegistry.instance;
    final codePoint = registry.lookup(iconName, variant);

    if (codePoint == null) {
      return Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            _getIconAbbreviation(iconName),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.5,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontFamily: 'NotoSerifSC',
            ),
          ),
        ),
      );
    }

    final fontFamily = registry.fontFamilyFor(iconName, variant);

    return Center(
      child: Text(
        String.fromCharCode(codePoint),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: 1.0,
          color: colorScheme.onPrimaryContainer,
          fontFamilyFallback: const <String>[],
        ),
      ),
    );
  }

  String _getIconAbbreviation(String iconName) {
    final parts = iconName.split('_');
    if (parts.length == 1) {
      return parts[0]
          .substring(0, parts[0].length > 2 ? 2 : parts[0].length)
          .toUpperCase();
    }
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Widget _buildImageIcon(
    LocalPlugin plugin,
    String relativePath,
    ColorScheme colorScheme,
  ) {
    final imageUrl = 'http://127.0.0.1:$sandboxServerPort/${plugin.id}/$relativePath';
    final lowerPath = relativePath.toLowerCase();
    final isSvg = lowerPath.endsWith('.svg');

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: size,
          height: size,
          child: isSvg
              ? SvgPicture.network(
                  imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  placeholderBuilder: (_) => _buildDefaultIcon(colorScheme),
                )
              : Image.network(
                  imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => _buildDefaultIcon(colorScheme),
                ),
        ),
      ),
    );
  }
}
