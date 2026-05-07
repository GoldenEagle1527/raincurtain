import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_data_manager.dart';

/// 插件数据详情页面
/// 显示单个插件的 LocalStorage 详细数据
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
      body: LocalStorageDetailsView(pluginId: pluginId),
    );
  }
}

/// LocalStorage 详情视图
class LocalStorageDetailsView extends StatelessWidget {
  final String pluginId;

  const LocalStorageDetailsView({super.key, required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final dataManager = context.watch<PluginDataManager>();

    if (!dataManager.isInit) {
      return const Center(child: CircularProgressIndicator());
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: dataManager.localStorageManager.loadLocalStorage(pluginId),
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

        final storage = snapshot.data ?? {};

        if (storage.isEmpty) {
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
                  '暂无 LocalStorage 数据',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: storage.length,
          itemBuilder: (context, index) {
            final key = storage.keys.elementAt(index);
            final value = storage[key].toString();

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text(
                  key,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  value.length > 50 ? '${value.substring(0, 50)}...' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DataRow(
                          label: '键',
                          value: key,
                          onCopy: () => _copyToClipboard(context, key),
                        ),
                        _DataRow(
                          label: '值',
                          value: value,
                          onCopy: () => _copyToClipboard(context, value),
                        ),
                        _DataRow(
                          label: '大小',
                          value: '${value.length} 字符',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

/// 数据行组件
class _DataRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _DataRow({
    required this.label,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
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
