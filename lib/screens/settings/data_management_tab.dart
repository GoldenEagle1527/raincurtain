import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_data_manager.dart';
import '../../models/plugin_manager.dart';
import 'plugin_data_details_page.dart';

/// 数据管理标签页
class DataManagementTab extends StatefulWidget {
  const DataManagementTab({super.key});

  @override
  State<DataManagementTab> createState() => _DataManagementTabState();
}

class _DataManagementTabState extends State<DataManagementTab> {
  Map<String, PluginDataStats>? _dataStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDataStats();
  }

  Future<void> _loadDataStats() async {
    setState(() => _isLoading = true);

    final dataManager = context.read<PluginDataManager>();
    if (!dataManager.isInit) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!dataManager.isInit) {
        setState(() => _isLoading = false);
        return;
      }
    }

    final stats = await dataManager.getAllPluginsDataStats();
    if (mounted) {
      setState(() {
        _dataStats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDataStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 存储目录卡片
          _buildStorageDirectoryCard(context),

          const SizedBox(height: 16),

          // 总体统计卡片
          _buildOverallStatsCard(context),

          const SizedBox(height: 16),

          // 插件数据列表
          _buildPluginDataList(context),
        ],
      ),
    );
  }

  Widget _buildStorageDirectoryCard(BuildContext context) {
    final dataManager = context.watch<PluginDataManager>();

    if (!dataManager.isInit) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.folder_open),
          title: Text('插件存储目录'),
          subtitle: Text('正在初始化...'),
        ),
      );
    }

    final storagePath = dataManager.dataDir.path;

    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_open),
        title: const Text('插件存储目录'),
        subtitle: Text(
          storagePath,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: '打开目录',
          onPressed: () => _openDirectory(storagePath),
        ),
      ),
    );
  }

  Widget _buildOverallStatsCard(BuildContext context) {
    if (_isLoading || _dataStats == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final totalSize = _dataStats!.values.fold<int>(
      0,
      (sum, stats) => sum + stats.totalSize,
    );
    final totalPlugins = _dataStats!.length;
    final totalItems = _dataStats!.values.fold<int>(
      0,
      (sum, stats) => sum + stats.totalItems,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '存储统计',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.extension,
                  label: '插件数量',
                  value: '$totalPlugins',
                ),
                _StatItem(
                  icon: Icons.data_object,
                  label: '数据项',
                  value: '$totalItems',
                ),
                _StatItem(
                  icon: Icons.storage,
                  label: '总存储',
                  value: PluginDataManager.formatBytes(totalSize),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPluginDataList(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_dataStats == null || _dataStats!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无插件数据',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '插件使用 LocalStorage 后会在此显示',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final pluginManager = context.watch<PluginManager>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            '插件数据详情',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ..._dataStats!.entries.map((entry) {
          final pluginId = entry.key;
          final stats = entry.value;
          final plugin = pluginManager.plugins
              .cast<LocalPlugin?>()
              .firstWhere(
                (p) => p?.id == pluginId,
                orElse: () => null,
              );

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: const Icon(Icons.extension),
              title: Text(plugin?.name ?? '未知插件'),
              subtitle: Text(
                  '总计: ${PluginDataManager.formatBytes(stats.totalSize)}'),
              children: [
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('LocalStorage'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${stats.localStorageItemCount} 项'),
                          Text(
                            PluginDataManager.formatBytes(
                                stats.localStorageSize),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmClearSpecificData(
                          context,
                          pluginId,
                          plugin?.name ?? '未知插件',
                          'LocalStorage',
                        ),
                        tooltip: '清除 LocalStorage',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.visibility),
                        label: const Text('查看详情'),
                        onPressed: () => _showPluginDataDetails(
                          context,
                          pluginId,
                          plugin?.name ?? '未知插件',
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('清除全部'),
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _confirmClearPluginData(
                          context,
                          pluginId,
                          plugin?.name ?? '未知插件',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _openDirectory(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前平台不支持打开目录')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开目录失败: $e')),
        );
      }
    }
  }

  Future<void> _confirmClearPluginData(
    BuildContext context,
    String pluginId,
    String pluginName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除全部数据'),
        content: Text('确定要清除 "$pluginName" 的所有 LocalStorage 数据吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('全部清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final dataManager = context.read<PluginDataManager>();
      await dataManager.clearAllDataForPlugin(pluginId);
      await _loadDataStats();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 "$pluginName" 的所有数据')),
        );
      }
    }
  }

  Future<void> _confirmClearSpecificData(
    BuildContext context,
    String pluginId,
    String pluginName,
    String dataType,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认清除 $dataType'),
        content: Text('确定要清除 "$pluginName" 的 $dataType 数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final dataManager = context.read<PluginDataManager>();
      await dataManager.clearLocalStorageForPlugin(pluginId);
      await _loadDataStats();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清除 "$pluginName" 的 $dataType 数据')),
        );
      }
    }
  }

  void _showPluginDataDetails(
    BuildContext context,
    String pluginId,
    String pluginName,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PluginDataDetailsPage(
          pluginId: pluginId,
          pluginName: pluginName,
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
