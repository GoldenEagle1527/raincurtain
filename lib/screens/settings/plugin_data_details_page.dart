import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_data_manager.dart';

/// 插件数据详情页面
/// 显示单个插件的存储表及其数据行
class PluginDataDetailsPage extends StatelessWidget {
  final String pluginId;
  final String pluginName;

  const PluginDataDetailsPage({
    super.key,
    required this.pluginId,
    required this.pluginName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pluginName),
      ),
      body: StorageDetailsView(pluginId: pluginId),
    );
  }
}

/// 存储详情视图
class StorageDetailsView extends StatelessWidget {
  final String pluginId;

  const StorageDetailsView({super.key, required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final dataManager = context.watch<PluginDataManager>();

    if (!dataManager.isInit) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<List<String>>(
      future: dataManager.pluginStorageManager.getShortTableNames(pluginId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  '加载失败',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final tableNames = snapshot.data ?? [];

        if (tableNames.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无存储数据',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tableNames.length,
          itemBuilder: (context, index) {
            return _StorageTableCard(
              pluginId: pluginId,
              tableName: tableNames[index],
            );
          },
        );
      },
    );
  }
}

/// 单个存储表卡片
class _StorageTableCard extends StatelessWidget {
  final String pluginId;
  final String tableName;

  const _StorageTableCard({
    required this.pluginId,
    required this.tableName,
  });

  @override
  Widget build(BuildContext context) {
    final dataManager = context.watch<PluginDataManager>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: dataManager.pluginStorageManager.query(
          pluginId,
          tableName,
          limit: 100,
        ),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting;

          return ExpansionTile(
            title: Text(
              tableName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: isLoading
                ? const Text('加载中...')
                : Text('${rows.length} 行'),
            children: [
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '表中暂无数据',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              else ...[
                // 数据行列表
                ...rows.map((row) => _DataRowTile(row: row)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 数据行展示
class _DataRowTile extends StatelessWidget {
  final Map<String, dynamic> row;

  const _DataRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final id = row['_id']?.toString() ?? '?';
    final entries = row.entries.where((e) => e.key != '_id').toList();
    final preview = entries
        .take(3)
        .map((e) => '${e.key}: ${_formatValue(e.value)}')
        .join(', ');
    final suffix = entries.length > 3 ? ', ...' : '';

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(
        '#$id',
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        '$preview$suffix',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries
                .map((e) => _FieldRow(
                      label: e.key,
                      value: _formatValue(e.value),
                      onCopy: () => _copyToClipboard(
                          context, _formatValue(e.value)),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    return value.toString();
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 字段行组件
class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _FieldRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: value.length > 20 ? 'monospace' : null,
                  ),
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: onCopy,
              tooltip: '复制',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
