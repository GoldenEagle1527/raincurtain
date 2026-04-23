
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/tab_manager.dart';
import '../utils/responsive_helper.dart';
import '../widgets/plugin_icon_widget.dart';
import '../widgets/plugin_upgrade_dialog.dart';

/// 插件市场视图
/// 使用 MD3 组件和主题色系统
class MarketView extends StatelessWidget {
  const MarketView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginManager>(
      builder: (context, pluginManager, child) {
        if (!pluginManager.isInit) {
          return const Center(child: CircularProgressIndicator());
        }

        final plugins = pluginManager.plugins;
        final colorScheme = Theme.of(context).colorScheme;
        final padding = ResponsiveHelper.getContentPadding(context);

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 插件列表标题
              Text(
                '已安装的插件 (${plugins.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: padding * 0.5),
              // 插件列表
              Expanded(
                child: plugins.isEmpty
                    ? _buildEmptyState(context)
                    : _buildPluginList(context, plugins, pluginManager),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 构建空状态
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无已安装的插件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击上方按钮安装新插件',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建插件列表
  Widget _buildPluginList(
    BuildContext context,
    List<LocalPlugin> plugins,
    PluginManager pluginManager,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final spacing = ResponsiveHelper.getListItemSpacing(context);
    
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: plugins.length,
      separatorBuilder: (context, index) => SizedBox(height: spacing),
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return _buildPluginCard(context, plugin, pluginManager, colorScheme);
      },
    );
  }
  
  /// 构建插件卡片
  Widget _buildPluginCard(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: PluginIconWidget(plugin: plugin),
        title: Text(
          plugin.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                plugin.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '版本：${plugin.version}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '作者：${plugin.author}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.upgrade_outlined),
              color: colorScheme.primary,
              onPressed: () => _handleUpgrade(context, plugin, pluginManager),
              tooltip: '升级',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: colorScheme.error,
              onPressed: () => _showUninstallDialog(context, plugin, pluginManager),
              tooltip: '卸载',
            ),
          ],
        ),
        onTap: () {
          Provider.of<TabManager>(context, listen: false).openOrSwitchTab(plugin);
        },
      ),
    );
  }
  
  /// 处理插件升级
  Future<void> _handleUpgrade(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    
    try {
      final upgradeInfo = await pluginManager.prepareUpgrade(plugin.id);
      
      if (upgradeInfo == null) {
        return; // 用户取消了选择
      }
      
      if (!context.mounted) return;
      
      // 显示升级确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => PluginUpgradeDialog(upgradeInfo: upgradeInfo),
      );
      
      if (confirmed != true) {
        return;
      }
      
      if (!context.mounted) return;
      
      // 执行升级
      await pluginManager.upgradePlugin(plugin.id, upgradeInfo.zipFile);
      
      if (!context.mounted) return;
      
      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${plugin.name} 已升级到 v${upgradeInfo.newManifest.version}'),
          backgroundColor: colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('升级失败: $e'),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }
  
  /// 显示卸载确认对话框
  void _showUninstallDialog(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: colorScheme.error,
          size: 32,
        ),
        title: const Text('卸载确认'),
        content: Text('确定要卸载插件 "${plugin.name}" 吗？\n此操作不可撤销。'),
        actions: [
          // 取消按钮
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          // 卸载按钮
          FilledButton(
            onPressed: () {
              pluginManager.uninstallPlugin(plugin.id);
              Navigator.pop(context);
              
              // 显示成功提示
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已卸载 ${plugin.name}'),
                  backgroundColor: colorScheme.primary,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }
}

