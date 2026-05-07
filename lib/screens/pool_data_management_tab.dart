import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pool_manager.dart';
import '../models/pool_plugin.dart';
import '../models/plugin_manager.dart';
import '../models/variable_pool_manager.dart';
import '../models/variable.dart';
import '../utils/responsive_helper.dart';
import '../widgets/plugin_icon_widget.dart';
import '../widgets/plugin_io_config_dialog.dart';

/// 数据管理标签页
class PoolDataManagementTab extends StatefulWidget {
  final String poolId;

  const PoolDataManagementTab({super.key, required this.poolId});

  @override
  State<PoolDataManagementTab> createState() => _PoolDataManagementTabState();
}

class _PoolDataManagementTabState extends State<PoolDataManagementTab> {
  bool _showVariables = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<VariablePoolManager>()
          .ensureLoaded(widget.poolId)
          .then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final poolManager = context.watch<PoolManager>();
    final pluginManager = context.watch<PluginManager>();
    final variablePoolManager = context.watch<VariablePoolManager>();
    final colorScheme = Theme.of(context).colorScheme;
    final padding = ResponsiveHelper.getContentPadding(context);
    final spacing = ResponsiveHelper.getListItemSpacing(context);

    final plugins = poolManager.getPoolPlugins(widget.poolId);
    final variables = variablePoolManager.getPoolVariables(widget.poolId);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 插件列表标题行 ──────────────────────────────
          Row(
            children: [
              Text(
                '池内插件 (${plugins.length})',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () =>
                    _showAddPluginDialog(context, poolManager, pluginManager),
                icon: const Icon(Icons.add),
                label: const Text('添加插件'),
              ),
            ],
          ),
          SizedBox(height: padding * 0.5),

          // ── 插件列表 ────────────────────────────────────
          if (plugins.isEmpty)
            _buildEmptyPluginState(context)
          else
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                buildDefaultDragHandles: false,
                itemCount: plugins.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  poolManager.reorderPlugins(
                      widget.poolId, oldIndex, newIndex);
                },
                proxyDecorator: (child, index, animation) => Material(
                  elevation: 4,
                  color: Colors.transparent,
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final pp = plugins[index];
                  final localPlugin = pluginManager.plugins
                      .cast<LocalPlugin?>()
                      .firstWhere((p) => p?.id == pp.pluginId,
                          orElse: () => null);

                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(pp.id),
                    index: index,
                    child: _buildPluginCard(
                      context: context,
                      pp: pp,
                      localPlugin: localPlugin,
                      colorScheme: colorScheme,
                      spacing: spacing,
                      poolManager: poolManager,
                      variablePoolManager: variablePoolManager,
                    ),
                  );
                },
              ),
            ),

          // ── 变量池折叠区 ────────────────────────────────
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showVariables = !_showVariables),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    '变量池 (${variables.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    _showVariables ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          if (_showVariables) ...[
            SizedBox(height: padding * 0.5),
            if (variables.isEmpty)
              _buildEmptyVariableState(context)
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: variables.length,
                  separatorBuilder: (_, __) => SizedBox(height: spacing),
                  itemBuilder: (context, index) {
                    final variable = variables.values.toList()[index];
                    return _buildVariableCard(
                        context, variable, variablePoolManager, colorScheme);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── 插件卡片（与 MarketView._buildPluginCard 一致的风格）──────────
  Widget _buildPluginCard({
    required BuildContext context,
    required PoolPlugin pp,
    required LocalPlugin? localPlugin,
    required ColorScheme colorScheme,
    required double spacing,
    required PoolManager poolManager,
    required VariablePoolManager variablePoolManager,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: spacing),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: localPlugin != null
              ? PluginIconWidget(plugin: localPlugin)
              : _fallbackIcon(colorScheme),
          title: Text(
            localPlugin?.name ?? '未知插件',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
          ),
          subtitle: localPlugin == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '插件 ID: ${pp.pluginId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localPlugin.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '版本：${localPlugin.version}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '作者：${localPlugin.author}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      ),
                      // 映射摘要
                      if (pp.inputMappings.isNotEmpty ||
                          pp.outputMappings.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildMappingSummary(context, pp, colorScheme),
                      ],
                    ],
                  ),
                ),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 配置按钮
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                tooltip: '配置映射',
                onPressed: localPlugin != null
                    ? () => _showIOConfigDialog(
                          context,
                          pp,
                          localPlugin,
                          poolManager,
                          variablePoolManager,
                        )
                    : null,
              ),
              // 移除按钮
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: colorScheme.error,
                tooltip: '从池中移除',
                onPressed: () => _confirmRemovePlugin(
                  context,
                  pp,
                  localPlugin?.name ?? '未知插件',
                  poolManager,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 映射配置摘要标签
  Widget _buildMappingSummary(
    BuildContext context,
    PoolPlugin pp,
    ColorScheme colorScheme,
  ) {
    final chips = <Widget>[];
    for (final e in pp.inputMappings.entries) {
      chips.add(_MappingChip(
        icon: Icons.download_outlined,
        label: '${e.key} ← ${e.value}',
        color: colorScheme.primaryContainer,
        textColor: colorScheme.onPrimaryContainer,
      ));
    }
    for (final e in pp.outputMappings.entries) {
      chips.add(_MappingChip(
        icon: Icons.upload_outlined,
        label: '${e.key} → ${e.value}',
        color: colorScheme.secondaryContainer,
        textColor: colorScheme.onSecondaryContainer,
      ));
    }
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }

  Widget _fallbackIcon(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.extension_off_outlined,
          color: colorScheme.onErrorContainer),
    );
  }

  // ── 变量卡片 ─────────────────────────────────────────────────────
  Widget _buildVariableCard(
    BuildContext context,
    Variable variable,
    VariablePoolManager variablePoolManager,
    ColorScheme colorScheme,
  ) {
    final valueStr = variable.value?.toString() ?? 'null';
    final shortValue =
        valueStr.length > 80 ? '${valueStr.substring(0, 80)}...' : valueStr;

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _typeIcon(variable.type),
            color: colorScheme.onTertiaryContainer,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              variable.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(
                variable.type,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            shortValue,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: colorScheme.error,
          tooltip: '删除变量',
          onPressed: () => variablePoolManager.deleteVariable(
            widget.poolId,
            variable.name,
          ),
        ),
      ),
    );
  }

  // ── 空状态 ─────────────────────────────────────────────────────
  Widget _buildEmptyPluginState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 32),
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有插件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角「添加插件」',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmptyVariableState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          '变量池为空',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  // ── 类型图标 ───────────────────────────────────────────────────
  IconData _typeIcon(String type) {
    switch (type) {
      case 'string':
        return Icons.text_fields;
      case 'number':
        return Icons.numbers;
      case 'boolean':
        return Icons.toggle_on_outlined;
      case 'object':
        return Icons.data_object;
      case 'array':
        return Icons.data_array;
      default:
        return Icons.circle_outlined;
    }
  }

  // ── 对话框 ─────────────────────────────────────────────────────
  Future<void> _showAddPluginDialog(
    BuildContext context,
    PoolManager poolManager,
    PluginManager pluginManager,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final allPlugins = pluginManager.plugins;
    if (allPlugins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有已安装的插件')),
      );
      return;
    }

    final selected = await showDialog<LocalPlugin>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择插件'),
        content: SizedBox(
          width: 480,
          height: 480,
          child: ListView.separated(
            itemCount: allPlugins.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final plugin = allPlugins[index];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: PluginIconWidget(plugin: plugin),
                  title: Text(
                    plugin.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    plugin.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  onTap: () => Navigator.pop(ctx, plugin),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selected != null && context.mounted) {
      await poolManager.addPluginToPool(widget.poolId, selected.id);
    }
  }

  Future<void> _showIOConfigDialog(
    BuildContext context,
    PoolPlugin pp,
    LocalPlugin plugin,
    PoolManager poolManager,
    VariablePoolManager variablePoolManager,
  ) async {
    final result = await showDialog<
        ({
          Map<String, String> inputMappings,
          Map<String, String> outputMappings
        })>(
      context: context,
      builder: (ctx) => PluginIOConfigDialog(
        poolPlugin: pp,
        plugin: plugin,
        poolId: widget.poolId,
        variablePoolManager: variablePoolManager,
      ),
    );

    if (result != null && context.mounted) {
      await poolManager.updatePluginMappings(
        widget.poolId,
        pp.id,
        result.inputMappings,
        result.outputMappings,
      );
    }
  }

  Future<void> _confirmRemovePlugin(
    BuildContext context,
    PoolPlugin pp,
    String pluginName,
    PoolManager poolManager,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: colorScheme.error, size: 32),
        title: const Text('移除确认'),
        content: Text('确定要从池中移除插件 "$pluginName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await poolManager.removePluginFromPool(widget.poolId, pp.id);
    }
  }
}

// ── 映射摘要标签 ─────────────────────────────────────────────────
class _MappingChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  const _MappingChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
