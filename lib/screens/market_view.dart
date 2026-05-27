
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

  /// 构建插件网格
  /// 桌面端：3列，宽高比 2:1 的极客风横向卡片
  /// 手机端：单列纵向排列
  Widget _buildPluginGrid(
    BuildContext context,
    List<LocalPlugin> plugins,
    PluginManager pluginManager,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = ResponsiveHelper.isCompact(context);

    if (isCompact) {
      // 手机端：单列列表
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: plugins.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final plugin = plugins[index];
          return _buildCompactCard(context, plugin, pluginManager, colorScheme);
        },
      );
    }

    // 桌面端：3列网格，宽高比 2:1
    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.0,
      ),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return _buildDesktopCard(context, plugin, pluginManager, colorScheme);
      },
    );
  }

  /// 桌面端卡片：紧凑极客风，首字下沉式布局
  /// 左上角大图标如同段落首字母，文字紧贴环绕
  /// 右上角关闭按钮
  Widget _buildDesktopCard(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () {
          Provider.of<TabManager>(context, listen: false).openOrSwitchTab(plugin);
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 首字下沉式：图标在左上，名称紧挨图标右侧（第一行）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 图标作为"首字"
                      PluginIconWidget(plugin: plugin),
                      const SizedBox(width: 8),
                      // 名称 + 描述紧贴图标
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plugin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              plugin.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // 底部元信息，紧贴底边
                  Text(
                    'v${plugin.version} · ${plugin.author}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            // 右上角关闭按钮
            Positioned(
              top: 4,
              right: 4,
              child: SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: colorScheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  onPressed: () => _showUninstallDialog(context, plugin, pluginManager),
                  tooltip: '卸载',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 手机端卡片：单行紧凑显示，同样首字下沉风格
  Widget _buildCompactCard(
    BuildContext context,
    LocalPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: () {
          Provider.of<TabManager>(context, listen: false).openOrSwitchTab(plugin);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PluginIconWidget(plugin: plugin),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plugin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plugin.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: colorScheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  onPressed: () => _showUninstallDialog(context, plugin, pluginManager),
                  tooltip: '卸载',
                ),
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
            onPressed: () async {
              Navigator.pop(context);
              try {
                await pluginManager.uninstallPlugin(plugin.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已卸载 ${plugin.name}'),
                      backgroundColor: colorScheme.primary,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('卸载失败: $e'),
                      backgroundColor: colorScheme.error,
                    ),
                  );
                }
              }
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
