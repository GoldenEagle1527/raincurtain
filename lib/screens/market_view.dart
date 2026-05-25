
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/tab_manager.dart';
import '../utils/responsive_helper.dart';
import '../widgets/plugin_icon_widget.dart';

/// 插件市场视图
/// 使用 MD3 组件和主题色系统，一行3列网格卡片布局
class MarketView extends StatefulWidget {
  const MarketView({super.key});

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  /// 是否显示搜索框
  bool _isSearching = false;

  /// 搜索关键词
  String _searchQuery = '';

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 根据搜索关键词过滤插件列表
  List<LocalPlugin> _filterPlugins(List<LocalPlugin> plugins) {
    if (_searchQuery.isEmpty) return plugins;
    final query = _searchQuery.toLowerCase();
    return plugins.where((plugin) {
      return plugin.name.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginManager>(
      builder: (context, pluginManager, child) {
        if (!pluginManager.isInit) {
          return const Center(child: CircularProgressIndicator());
        }

        final plugins = pluginManager.plugins;
        final filteredPlugins = _filterPlugins(plugins);
        final colorScheme = Theme.of(context).colorScheme;
        final padding = ResponsiveHelper.getContentPadding(context);

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题栏 + 搜索
              _buildHeader(context, plugins.length, colorScheme, pluginManager),
              SizedBox(height: padding * 0.5),
              // 搜索框（动画展开）
              if (_isSearching) ...[
                _buildSearchBar(context, colorScheme),
                SizedBox(height: padding * 0.5),
              ],
              // 插件网格
              Expanded(
                child: filteredPlugins.isEmpty
                    ? _buildEmptyState(context)
                    : _buildPluginGrid(context, filteredPlugins, pluginManager),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建标题栏
  Widget _buildHeader(
    BuildContext context,
    int totalCount,
    ColorScheme colorScheme,
    PluginManager pluginManager,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '已安装的插件 ($totalCount)',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
        // 搜索按钮
        IconButton(
          icon: Icon(_isSearching ? Icons.search_off : Icons.search),
          tooltip: _isSearching ? '关闭搜索' : '搜索插件',
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchQuery = '';
                _searchController.clear();
              }
            });
          },
        ),
        // 刷新按钮
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新插件列表',
          onPressed: () => pluginManager.reloadPlugins(),
        ),
      ],
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '搜索插件名称...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
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
            _searchQuery.isNotEmpty ? Icons.search_off : Icons.inbox_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? '未找到匹配的插件' : '暂无已安装的插件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? '尝试使用其他关键词搜索' : '点击上方按钮安装新插件',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建插件网格（一行3列）
  Widget _buildPluginGrid(
    BuildContext context,
    List<LocalPlugin> plugins,
    PluginManager pluginManager,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return _buildPluginCard(context, plugin, pluginManager, colorScheme);
      },
    );
  }

  /// 构建插件卡片（适配网格布局）
  Widget _buildPluginCard(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Provider.of<TabManager>(context, listen: false).openOrSwitchTab(plugin);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：图标 + 卸载按钮
              Row(
                children: [
                  PluginIconWidget(plugin: plugin),
                  const Spacer(),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: colorScheme.error,
                      padding: EdgeInsets.zero,
                      onPressed: () => _showUninstallDialog(context, plugin, pluginManager),
                      tooltip: '卸载',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 插件名称
              Text(
                plugin.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              // 插件描述
              Expanded(
                child: Text(
                  plugin.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // 底部：版本 + 作者
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'v${plugin.version}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  Text(
                    plugin.author,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
