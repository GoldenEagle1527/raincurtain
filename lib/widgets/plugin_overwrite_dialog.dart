import 'package:flutter/material.dart';
import '../models/plugin_manager.dart';
import '../models/plugin_manifest.dart';

class PluginOverwriteDialog extends StatelessWidget {
  const PluginOverwriteDialog({
    super.key,
    required this.existingPlugin,
    required this.newManifest,
  });

  final LocalPlugin existingPlugin;
  final PluginManifest newManifest;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 比较版本
    final versionResult = existingPlugin.manifest.compareVersion(newManifest.version);
    
    IconData iconData;
    Color iconColor;
    String title;
    String versionInfo;
    
    switch (versionResult) {
      case VersionComparisonResult.newer:
        iconData = Icons.upgrade;
        iconColor = colorScheme.primary;
        title = '发现新版本';
        versionInfo = '当前版本: ${existingPlugin.version}\n新版本: ${newManifest.version}';
        break;
      case VersionComparisonResult.older:
        iconData = Icons.warning_amber_rounded;
        iconColor = colorScheme.error;
        title = '版本较旧';
        versionInfo = '当前版本: ${existingPlugin.version}\n选择的版本: ${newManifest.version}';
        break;
      case VersionComparisonResult.same:
        iconData = Icons.refresh;
        iconColor = colorScheme.secondary;
        title = '版本相同';
        versionInfo = '当前版本和选择的版本都是: ${existingPlugin.version}';
        break;
    }

    return AlertDialog(
      icon: Icon(
        iconData,
        color: iconColor,
        size: 32,
      ),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '插件「${existingPlugin.name}」已安装',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(versionInfo),
          const SizedBox(height: 12),
          Text(
            '覆盖安装将保留插件数据（LocalStorage）',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('覆盖安装'),
        ),
      ],
    );
  }
}
