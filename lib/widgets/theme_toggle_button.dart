import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

/// 主题切换按钮
/// 提供三种主题模式选择: 亮色、暗色、跟随系统
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return PopupMenuButton<ThemeMode>(
          icon: Icon(themeProvider.getThemeModeIcon(themeProvider.themeMode)),
          tooltip: '切换主题',
          onSelected: (ThemeMode mode) {
            themeProvider.setThemeMode(mode);
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem(
              value: ThemeMode.light,
              child: Row(
                children: [
                  Icon(
                    Icons.light_mode,
                    color: themeProvider.themeMode == ThemeMode.light
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '亮色模式',
                    style: TextStyle(
                      color: themeProvider.themeMode == ThemeMode.light
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: themeProvider.themeMode == ThemeMode.light
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: ThemeMode.dark,
              child: Row(
                children: [
                  Icon(
                    Icons.dark_mode,
                    color: themeProvider.themeMode == ThemeMode.dark
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '暗色模式',
                    style: TextStyle(
                      color: themeProvider.themeMode == ThemeMode.dark
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: themeProvider.themeMode == ThemeMode.dark
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: ThemeMode.system,
              child: Row(
                children: [
                  Icon(
                    Icons.brightness_auto,
                    color: themeProvider.themeMode == ThemeMode.system
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '跟随系统',
                    style: TextStyle(
                      color: themeProvider.themeMode == ThemeMode.system
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: themeProvider.themeMode == ThemeMode.system
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 简单的主题切换图标按钮
/// 点击直接切换亮色/暗色模式
class ThemeToggleIconButton extends StatelessWidget {
  const ThemeToggleIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return IconButton(
          icon: Icon(
            themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
          ),
          tooltip: themeProvider.isDarkMode ? '切换到亮色模式' : '切换到暗色模式',
          onPressed: () {
            themeProvider.toggleThemeMode();
          },
        );
      },
    );
  }
}

/// 主题切换分段按钮
/// 以分段按钮的形式展示三种主题模式
class ThemeToggleSegmentedButton extends StatelessWidget {
  const ThemeToggleSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.light,
              label: const Text('亮色'),
              icon: const Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: const Text('暗色'),
              icon: const Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: const Text('自动'),
              icon: const Icon(Icons.brightness_auto),
            ),
          ],
          selected: {themeProvider.themeMode},
          onSelectionChanged: (Set<ThemeMode> selection) {
            themeProvider.setThemeMode(selection.first);
          },
        );
      },
    );
  }
}
