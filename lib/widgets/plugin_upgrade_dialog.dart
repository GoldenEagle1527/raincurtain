
import 'package:flutter/material.dart';
import '../models/plugin_manager.dart';
import '../models/plugin_manifest.dart';

class PluginUpgradeDialog extends StatelessWidget {
  const PluginUpgradeDialog({
    super.key,
    required this.upgradeInfo,
  });

  final PluginUpgradeInfo upgradeInfo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData iconData;
    Color iconColor;
    String title;
    String content;
    String confirmButtonText;

    switch (upgradeInfo.versionResult) {
      case VersionComparisonResult.newer:
        iconData = Icons.upgrade;
        iconColor = colorScheme.primary;
        title = '发现新版本';
        content = '当前版本: ${upgradeInfo.existingVersion}\n'
            '新版本: ${upgradeInfo.newManifest.version}\n\n'
            '是否要升级插件？';
        confirmButtonText = '升级';
        break;
      case VersionComparisonResult.older:
        iconData = Icons.warning_amber_rounded;
        iconColor = colorScheme.error;
        title = '版本较旧';
        content = '当前版本: ${upgradeInfo.existingVersion}\n'
            '选择的版本: ${upgradeInfo.newManifest.version}\n\n'
            '是否要安装较旧版本？';
        confirmButtonText = '安装';
        break;
      case VersionComparisonResult.same:
        iconData = Icons.refresh;
        iconColor = colorScheme.secondary;
        title = '版本相同';
        content = '当前版本和选择的版本都是: ${upgradeInfo.existingVersion}\n\n'
            '是否要覆盖安装？';
        confirmButtonText = '覆盖';
        break;
    }

    return AlertDialog(
      icon: Icon(
        iconData,
        color: iconColor,
        size: 32,
      ),
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmButtonText),
        ),
      ],
    );
  }
}
