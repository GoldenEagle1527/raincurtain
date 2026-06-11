import 'package:flutter/material.dart';
import '../../models/plugin_icon.dart';
import '../../utils/material_icons_registry.dart';

class MarketPluginIconWidget extends StatelessWidget {
  final String? iconString;
  final String name;
  final double size;

  const MarketPluginIconWidget({
    super.key,
    required this.iconString,
    required this.name,
    this.size = 32.0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size + 16,
      height: size + 16,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: _buildIconContent(colorScheme),
      ),
    );
  }

  Widget _buildIconContent(ColorScheme colorScheme) {
    if (iconString != null && iconString!.startsWith('material:')) {
      final iconName = iconString!.substring('material:'.length).trim();
      return _buildMaterialIcon(iconName, colorScheme);
    }
    return _buildAbbreviation(colorScheme);
  }

  Widget _buildMaterialIcon(String iconName, ColorScheme colorScheme) {
    final registry = MaterialIconsRegistry.instance;
    final codePoint =
        registry.lookup(iconName, MaterialIconVariant.filled);

    if (codePoint == null) {
      return _buildAbbreviation(colorScheme);
    }

    final fontFamily = registry.fontFamilyFor(iconName, MaterialIconVariant.filled);

    return Text(
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
    );
  }

  Widget _buildAbbreviation(ColorScheme colorScheme) {
    final abbr = name
        .substring(0, name.length > 2 ? 2 : name.length)
        .toUpperCase();
    return Text(
      abbr,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size * 0.5,
        color: colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
        fontFamily: 'NotoSerifSC',
      ),
    );
  }
}
