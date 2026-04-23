import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/color_profile.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/theme_toggle_button.dart';

/// 主题设置标签页
class ThemeSettingsTab extends StatelessWidget {
  const ThemeSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 主题模式选择卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题模式',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const ThemeToggleSegmentedButton(),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 主题预览卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题预览',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                // 显示当前主题的颜色方案
                _buildColorPreview(context),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),

        // 主题配色卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题配色',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _buildColorProfileSelector(context),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 主题信息卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '主题信息',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.brightness_6),
                          title: const Text('当前模式'),
                          subtitle: Text(_getThemeModeText(themeProvider.themeMode)),
                        ),
                        ListTile(
                          leading: const Icon(Icons.dark_mode),
                          title: const Text('实际显示'),
                          subtitle: Text(themeProvider.isDarkMode ? '暗色主题' : '亮色主题'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildColorPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ColorChip(color: colorScheme.primary, label: 'Primary'),
        _ColorChip(color: colorScheme.secondary, label: 'Secondary'),
        _ColorChip(color: colorScheme.tertiary, label: 'Tertiary'),
        _ColorChip(color: colorScheme.surface, label: 'Surface'),
        _ColorChip(color: colorScheme.error, label: 'Error'),
        _ColorChip(color: colorScheme.primaryContainer, label: 'Primary Container'),
      ],
    );
  }
  
  Widget _buildColorProfileSelector(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: kBuiltinProfiles.map((profile) {
              final isSelected = themeProvider.colorProfile.id == profile.id;
              
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () {
                    themeProvider.setColorProfile(profile);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: profile.seed,
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  color: ThemeData.estimateBrightnessForColor(profile.seed) == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                  size: 20,
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          profile.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '亮色模式';
      case ThemeMode.dark:
        return '暗色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final String label;
  
  const _ColorChip({
    required this.color,
    required this.label,
  });
  
  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final textColor = brightness == Brightness.dark ? Colors.white : Colors.black;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
