import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/window_config_manager.dart';
import '../../models/hotkey_config.dart';

class HotkeySettingsTab extends StatefulWidget {
  const HotkeySettingsTab({super.key});

  @override
  State<HotkeySettingsTab> createState() => _HotkeySettingsTabState();
}

class _HotkeySettingsTabState extends State<HotkeySettingsTab> {
  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return const Center(
        child: Text('快捷键功能仅在Windows平台可用'),
      );
    }

    final configManager = Provider.of<WindowConfigManager>(context);
    final config = configManager.hotkeyConfig;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '全局快捷键',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '设置一个全局快捷键来快速唤起雨幕窗口',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        SwitchListTile(
          title: const Text('启用全局快捷键'),
          subtitle: const Text('开启后可以使用快捷键快速显示窗口'),
          value: config.enabled,
          onChanged: (value) async {
            if (!value) {
              await configManager.disableHotkey();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已禁用全局快捷键')),
              );
            } else if (config.keyCode != 0) {
              final success = await configManager.setHotkey(
                config.modifiers,
                config.keyCode,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? '已启用全局快捷键' : '启用快捷键失败'),
                ),
              );
            } else {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先设置快捷键')),
              );
            }
          },
        ),

        const SizedBox(height: 16),

        Card(
          child: ListTile(
            title: const Text('当前快捷键'),
            subtitle: Text(
              config.description,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            trailing: FilledButton.tonal(
              onPressed: () => _showHotkeyDialog(context, configManager),
              child: const Text('设置'),
            ),
          ),
        ),

        const SizedBox(height: 24),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '使用说明',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoItem('• 点击"设置"按钮后,选择您想要的快捷键组合'),
                _buildInfoItem('• 建议使用 Ctrl/Alt/Shift + 字母/数字 的组合'),
                _buildInfoItem('• 避免使用系统已占用的快捷键'),
                _buildInfoItem('• 设置为空表示不使用快捷键功能'),
                _buildInfoItem('• 窗口隐藏时按快捷键可快速显示'),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '常用快捷键推荐',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetChip(context, configManager, 'Ctrl + Alt + R',
                        HotkeyConfig.MOD_CONTROL | HotkeyConfig.MOD_ALT, 0x52),
                    _buildPresetChip(context, configManager, 'Ctrl + Shift + R',
                        HotkeyConfig.MOD_CONTROL | HotkeyConfig.MOD_SHIFT, 0x52),
                    _buildPresetChip(context, configManager, 'Ctrl + Alt + Space',
                        HotkeyConfig.MOD_CONTROL | HotkeyConfig.MOD_ALT, 0x20),
                    _buildPresetChip(context, configManager, 'Win + R',
                        HotkeyConfig.MOD_WIN, 0x52),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPresetChip(
    BuildContext context,
    WindowConfigManager manager,
    String label,
    int modifiers,
    int keyCode,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () async {
        final success = await manager.setHotkey(modifiers, keyCode);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '快捷键已设置为 $label' : '设置失败,该快捷键可能已被占用'),
          ),
        );
      },
    );
  }

  void _showHotkeyDialog(BuildContext context, WindowConfigManager manager) {
    showDialog(
      context: context,
      builder: (context) => _HotkeyPickerDialog(manager: manager),
    );
  }
}

class _HotkeyPickerDialog extends StatefulWidget {
  final WindowConfigManager manager;

  const _HotkeyPickerDialog({required this.manager});

  @override
  State<_HotkeyPickerDialog> createState() => _HotkeyPickerDialogState();
}

class _HotkeyPickerDialogState extends State<_HotkeyPickerDialog> {
  int _selectedModifiers = 0;
  int _selectedKey = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置快捷键'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择修饰键:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Ctrl'),
                  selected: _selectedModifiers & HotkeyConfig.MOD_CONTROL != 0,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedModifiers |= HotkeyConfig.MOD_CONTROL;
                      } else {
                        _selectedModifiers &= ~HotkeyConfig.MOD_CONTROL;
                      }
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Alt'),
                  selected: _selectedModifiers & HotkeyConfig.MOD_ALT != 0,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedModifiers |= HotkeyConfig.MOD_ALT;
                      } else {
                        _selectedModifiers &= ~HotkeyConfig.MOD_ALT;
                      }
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Shift'),
                  selected: _selectedModifiers & HotkeyConfig.MOD_SHIFT != 0,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedModifiers |= HotkeyConfig.MOD_SHIFT;
                      } else {
                        _selectedModifiers &= ~HotkeyConfig.MOD_SHIFT;
                      }
                    });
                  },
                ),
                FilterChip(
                  label: const Text('Win'),
                  selected: _selectedModifiers & HotkeyConfig.MOD_WIN != 0,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedModifiers |= HotkeyConfig.MOD_WIN;
                      } else {
                        _selectedModifiers &= ~HotkeyConfig.MOD_WIN;
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('选择按键:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _selectedKey == 0 ? null : _selectedKey,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '选择一个按键',
              ),
              items: _buildKeyItems(),
              onChanged: (value) {
                setState(() {
                  _selectedKey = value ?? 0;
                });
              },
            ),
            if (_selectedModifiers != 0 && _selectedKey != 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getHotkeyPreview(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedModifiers == 0 || _selectedKey == 0
              ? null
              : () async {
                  final success = await widget.manager.setHotkey(
                    _selectedModifiers,
                    _selectedKey,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? '快捷键设置成功' : '设置失败,该快捷键可能已被占用'),
                      ),
                    );
                  }
                },
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<DropdownMenuItem<int>> _buildKeyItems() {
    final items = <DropdownMenuItem<int>>[];

    // A-Z
    for (int i = 0x41; i <= 0x5A; i++) {
      items.add(DropdownMenuItem(
        value: i,
        child: Text(String.fromCharCode(i)),
      ));
    }

    // 0-9
    for (int i = 0x30; i <= 0x39; i++) {
      items.add(DropdownMenuItem(
        value: i,
        child: Text(String.fromCharCode(i)),
      ));
    }

    // F1-F12
    for (int i = 1; i <= 12; i++) {
      items.add(DropdownMenuItem(
        value: 0x6F + i,
        child: Text('F$i'),
      ));
    }

    // 特殊键
    items.add(const DropdownMenuItem(value: 0x20, child: Text('Space')));
    items.add(const DropdownMenuItem(value: 0x0D, child: Text('Enter')));
    items.add(const DropdownMenuItem(value: 0x1B, child: Text('Esc')));

    return items;
  }

  String _getHotkeyPreview() {
    final config = HotkeyConfig(
      enabled: true,
      modifiers: _selectedModifiers,
      keyCode: _selectedKey,
    );
    return config.description;
  }
}
