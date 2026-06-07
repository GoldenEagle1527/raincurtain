import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/market_plugin.dart';
import 'components/market_plugin_icon.dart';

import '../models/plugin_manager.dart';
import '../utils/responsive_helper.dart';
import '../services/market_service.dart';
import 'components/market_plugin_card.dart';
import 'components/market_tags_filter.dart';

/// 插件市场视图
/// 使用 MD3 组件和主题色系统，重构为双 Tab 布局（已安装、在线市场）
class MarketView extends StatefulWidget {
  const MarketView({super.key});

  @override
  State<MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<MarketView> {
  // ── 已安装插件状态 ──
  bool _isSearching = false;
  String _searchQuery = '';
  String _selectedLocalTag = '';
  final TextEditingController _searchController = TextEditingController();

  // ── 在线市场状态 ──
  List<MarketPlugin> _marketPlugins = [];
  bool _isLoadingMarket = false;
  String? _marketError;
  String _selectedMarketTag = '';

  bool _isSearchingMarket = false;
  String _searchQueryMarket = '';
  final TextEditingController _searchControllerMarket = TextEditingController();

  // 下载进度跟踪：[pluginId-version] -> 进度 0.0 ~ 1.0
  final Map<String, double> _downloadProgress = {};

  // 历史版本缓存：[pluginId] -> List<MarketPlugin>（已按 updated_at 降序）
  final Map<String, List<MarketPlugin>> _versionsCache = {};
  // 历史版本加载状态：[pluginId] -> true=加载中
  final Map<String, bool> _versionsLoading = {};

  @override
  void initState() {
    super.initState();
    // 首次载入在线插件列表
    _fetchMarketPlugins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchControllerMarket.dispose();
    super.dispose();
  }

  // 获取在线插件列表
  Future<void> _fetchMarketPlugins([String query = '']) async {
    if (_isLoadingMarket) return;
    setState(() {
      _isLoadingMarket = true;
      _marketError = null;
    });

    try {
      final list = await MarketService.fetchMarketPlugins(query);
      setState(() {
        _marketPlugins = list;
      });
    } catch (e) {
      setState(() {
        _marketError = e.toString();
      });
    } finally {
      setState(() {
        _isLoadingMarket = false;
      });
    }
  }

  // 拉取某插件全部历史版本（带缓存）
  Future<void> _fetchPluginVersions(String pluginId,
      {void Function()? onDone}) async {
    if (_versionsCache.containsKey(pluginId)) {
      onDone?.call();
      return;
    }
    if (_versionsLoading[pluginId] == true) return;

    setState(() {
      _versionsLoading[pluginId] = true;
    });

    try {
      final list = await MarketService.fetchPluginVersions(pluginId);
      if (mounted) {
        setState(() {
          _versionsCache[pluginId] = list;
        });
      }
    } catch (e) {
      debugPrint('[Market] 获取历史版本失败 ($pluginId): $e');
    } finally {
      if (mounted) {
        setState(() {
          _versionsLoading.remove(pluginId);
        });
      }
      onDone?.call();
    }
  }

  // 流式下载并调用 PluginManager 一键安装
  Future<void> _downloadAndInstall(
      MarketPlugin plugin, PluginManager pluginManager) async {
    final progressKey = '${plugin.pluginId}-${plugin.version}';
    setState(() {
      _downloadProgress[progressKey] = 0.0;
    });

    try {
      await MarketService.downloadAndInstall(
        plugin: plugin,
        pluginManager: pluginManager,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[progressKey] = progress;
          });
        },
      );

      final displayName =
          plugin.name.isNotEmpty ? plugin.name : plugin.pluginId;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件 "$displayName" v${plugin.version} 安装成功！'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Market] 下载安装异常: $e');
      final displayName =
          plugin.name.isNotEmpty ? plugin.name : plugin.pluginId;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件 "$displayName" v${plugin.version} 安装失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _downloadProgress.remove(progressKey);
      });
    }
  }

  /// 根据已安装搜索关键词与标签过滤插件列表
  List<LocalPlugin> _filterPlugins(List<LocalPlugin> plugins) {
    var list = plugins;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((plugin) {
        return plugin.name.toLowerCase().contains(query) ||
            plugin.id.toLowerCase().contains(query) ||
            plugin.description.toLowerCase().contains(query) ||
            plugin.author.toLowerCase().contains(query) ||
            plugin.manifest.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }
    if (_selectedLocalTag.isNotEmpty) {
      list = list.where((plugin) => plugin.manifest.tags.contains(_selectedLocalTag)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Consumer<PluginManager>(
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
                // 顶部标题与 Tab 选择栏
                _buildTabsHeader(
                    context, plugins.length, colorScheme, pluginManager),
                const SizedBox(height: 8),
                // Tab 内容视图
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: 已安装插件列表管理
                      _buildInstalledTabContent(
                          context, plugins, pluginManager, colorScheme, padding),
                      // Tab 2: 在线插件探索市场
                      _buildOnlineMarketTabContent(
                          context, pluginManager, colorScheme, padding),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRefreshMenu(BuildContext context, Offset position, PluginManager pluginManager) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'normal',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('普通刷新 (读取缓存)'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'force',
          child: Row(
            children: [
              Icon(Icons.rotate_right, size: 18),
              SizedBox(width: 8),
              Text('强制刷新 (重新扫描磁盘)'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'normal') {
        pluginManager.reloadPlugins();
      } else if (value == 'force') {
        _forceReload(context, pluginManager);
      }
    });
  }

  Future<void> _forceReload(BuildContext context, PluginManager pluginManager) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('正在强制重新扫描磁盘并加载插件元数据...'),
        duration: Duration(milliseconds: 800),
      ),
    );
    await pluginManager.reloadPlugins(force: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('强制刷新元数据完成！'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  /// 构建双 Tab 顶部标题与动作行
  Widget _buildTabsHeader(
    BuildContext context,
    int installedCount,
    ColorScheme colorScheme,
    PluginManager pluginManager,
  ) {
    return Row(
      children: [
        Expanded(
          child: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: '已安装 ($installedCount)'),
              const Tab(text: '在线市场'),
            ],
          ),
        ),
        // 智能刷新动作
        Builder(
          builder: (context) {
            return GestureDetector(
              onLongPressStart: (details) {
                final tabController = DefaultTabController.of(context);
                if (tabController.index == 0) {
                  _showRefreshMenu(context, details.globalPosition, pluginManager);
                }
              },
              onSecondaryTapDown: (details) {
                final tabController = DefaultTabController.of(context);
                if (tabController.index == 0) {
                  _showRefreshMenu(context, details.globalPosition, pluginManager);
                }
              },
              child: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新列表 (长按/右键可强制重载)',
                onPressed: () {
                  final tabController = DefaultTabController.of(context);
                  if (tabController.index == 0) {
                    pluginManager.reloadPlugins();
                  } else {
                    _fetchMarketPlugins(_searchQueryMarket);
                  }
                },
              ),
            );
          },
        ),
      ],
    );
  }

  /// 构建已安装 Tab 的内容
  Widget _buildInstalledTabContent(
    BuildContext context,
    List<LocalPlugin> plugins,
    PluginManager pluginManager,
    ColorScheme colorScheme,
    double padding,
  ) {
    final filteredPlugins = _filterPlugins(plugins);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '已安装的插件',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
          ],
        ),
        if (_isSearching) ...[
          const SizedBox(height: 8),
          _buildSearchBar(context, colorScheme),
        ],
        const SizedBox(height: 8),
        MarketTagsFilter(
          tags: plugins.expand((p) => p.manifest.tags).toSet().toList(),
          selectedTag: _selectedLocalTag,
          onTagSelected: (tag) {
            setState(() {
              _selectedLocalTag = tag;
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredPlugins.isEmpty
              ? _buildEmptyState(context)
              : _buildPluginGrid(context, filteredPlugins, pluginManager),
        ),
      ],
    );
  }

  /// 构建在线市场 Tab 的内容
  Widget _buildOnlineMarketTabContent(
    BuildContext context,
    PluginManager pluginManager,
    ColorScheme colorScheme,
    double padding,
  ) {
    final filteredMarket = _selectedMarketTag.isEmpty
        ? _marketPlugins
        : _marketPlugins.where((p) => p.tags.contains(_selectedMarketTag)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '探索在线插件',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                  _isSearchingMarket ? Icons.search_off : Icons.search),
              tooltip: _isSearchingMarket ? '关闭搜索' : '搜索在线插件',
              onPressed: () {
                setState(() {
                  _isSearchingMarket = !_isSearchingMarket;
                  if (!_isSearchingMarket) {
                    _searchQueryMarket = '';
                    _searchControllerMarket.clear();
                    _fetchMarketPlugins();
                  }
                });
              },
            ),
          ],
        ),
        if (_isSearchingMarket) ...[
          const SizedBox(height: 8),
          _buildOnlineSearchBar(context, colorScheme),
        ],
        const SizedBox(height: 8),
        MarketTagsFilter(
          tags: _marketPlugins.expand((p) => p.tags).toSet().toList(),
          selectedTag: _selectedMarketTag,
          onTagSelected: (tag) {
            setState(() {
              _selectedMarketTag = tag;
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoadingMarket
              ? const Center(child: CircularProgressIndicator())
              : _marketError != null
                  ? _buildMarketErrorState(context)
                  : filteredMarket.isEmpty
                      ? _buildOnlineEmptyState(context)
                      : _buildOnlineGrid(
                          context, filteredMarket, pluginManager, colorScheme),
        ),
      ],
    );
  }

  /// 构建已安装搜索框
  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '搜索本地插件名称...',
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
    );
  }

  /// 构建在线市场搜索框
  Widget _buildOnlineSearchBar(BuildContext context, ColorScheme colorScheme) {
    return TextField(
      controller: _searchControllerMarket,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '搜索在线插件 ID...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQueryMarket.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchControllerMarket.clear();
                  setState(() {
                    _searchQueryMarket = '';
                  });
                  _fetchMarketPlugins();
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (value) {
        setState(() {
          _searchQueryMarket = value;
        });
        _fetchMarketPlugins(value);
      },
    );
  }

  /// 在线市场错误界面
  Widget _buildMarketErrorState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: colorScheme.error),
          const SizedBox(height: 16),
          Text(
            '插件市场连接失败',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _marketError ?? '网络连接超时，请确认服务已正常部署',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('重试连接'),
            onPressed: () => _fetchMarketPlugins(_searchQueryMarket),
          ),
        ],
      ),
    );
  }

  /// 构建本地空状态
  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilter = _searchQuery.isNotEmpty || _selectedLocalTag.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.search_off : Icons.inbox_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter ? '未找到匹配的插件' : '暂无已安装的插件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter ? '尝试使用其他关键词或标签筛选' : '点击右下角按钮安装新插件',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建在线空状态
  Widget _buildOnlineEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilter = _searchQueryMarket.isNotEmpty || _selectedMarketTag.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.search_off : Icons.cloud_queue_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter ? '未找到符合条件的在线插件' : '在线插件市场暂无内容',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter ? '尝试更换搜索词或标签重新查询' : '点击右上角刷新，或稍后再试',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建已安装插件网格
  Widget _buildPluginGrid(
    BuildContext context,
    List<LocalPlugin> plugins,
    PluginManager pluginManager,
  ) {
    final isCompact = ResponsiveHelper.isCompact(context);

    if (isCompact) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: plugins.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final plugin = plugins[index];
          return MarketPluginCard(
            localPlugin: plugin,
            isDesktop: false,
            onUninstall: (p) => _showUninstallDialog(context, p, pluginManager),
          );
        },
      );
    }

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
        return MarketPluginCard(
          localPlugin: plugin,
          isDesktop: true,
          onUninstall: (p) => _showUninstallDialog(context, p, pluginManager),
        );
      },
    );
  }

  /// 构建在线插件网格
  Widget _buildOnlineGrid(
    BuildContext context,
    List<MarketPlugin> marketPlugins,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    final isCompact = ResponsiveHelper.isCompact(context);

    if (isCompact) {
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: marketPlugins.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final plugin = marketPlugins[index];
          final local = pluginManager.getPluginById(plugin.pluginId);
          final progressKey = '${plugin.pluginId}-${plugin.version}';
          final isDownloading = _downloadProgress.containsKey(progressKey);
          final downloadProgress = _downloadProgress[progressKey] ?? 0.0;

          return MarketPluginCard(
            marketPlugin: plugin,
            isDesktop: false,
            isDownloading: isDownloading,
            downloadProgress: downloadProgress,
            onInstall: (p) => _downloadAndInstall(p, pluginManager),
            onDetail: (p) => _showOnlineDetailDialog(context, p, pluginManager, local),
            onHistory: (p) => _showOnlineHistoryDialog(context, p, pluginManager, local),
          );
        },
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.0,
      ),
      itemCount: marketPlugins.length,
      itemBuilder: (context, index) {
        final plugin = marketPlugins[index];
        final local = pluginManager.getPluginById(plugin.pluginId);
        final progressKey = '${plugin.pluginId}-${plugin.version}';
        final isDownloading = _downloadProgress.containsKey(progressKey);
        final downloadProgress = _downloadProgress[progressKey] ?? 0.0;

        return MarketPluginCard(
          marketPlugin: plugin,
          isDesktop: true,
          isDownloading: isDownloading,
          downloadProgress: downloadProgress,
          onInstall: (p) => _downloadAndInstall(p, pluginManager),
          onDetail: (p) => _showOnlineDetailDialog(context, p, pluginManager, local),
          onHistory: (p) => _showOnlineHistoryDialog(context, p, pluginManager, local),
        );
      },
    );
  }

  /// 弹出在线插件详情对话框
  void _showOnlineDetailDialog(
    BuildContext context,
    MarketPlugin plugin,
    PluginManager pluginManager,
    LocalPlugin? local,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = plugin.name.isNotEmpty ? plugin.name : plugin.pluginId;
    final displayDesc = plugin.description.isNotEmpty ? plugin.description : '暂无功能描述。';
    final displayIcon = plugin.icon;
    final displayTags = plugin.tags;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final latestProgressKey = '${plugin.pluginId}-${plugin.version}';
            final isLatestDownloading =
                _downloadProgress.containsKey(latestProgressKey);
            final latestProgress =
                _downloadProgress[latestProgressKey] ?? 0.0;

            // 判断是否有任何版本正在下载
            final anyDownloading = _downloadProgress.keys
                .any((k) => k.startsWith('${plugin.pluginId}-'));

            Widget actionButton;
            if (isLatestDownloading) {
              actionButton = OutlinedButton.icon(
                icon: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text(
                    '正在下载 (${(latestProgress * 100).toStringAsFixed(0)}%)'),
                onPressed: null,
              );
            } else if (local == null) {
              actionButton = FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text('安装最新 v${plugin.version}'),
                onPressed: anyDownloading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _downloadAndInstall(plugin, pluginManager);
                      },
              );
            } else if (local.version != plugin.version) {
              actionButton = FilledButton.icon(
                icon: const Icon(Icons.update),
                label: Text('升级到 v${plugin.version}'),
                onPressed: anyDownloading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _downloadAndInstall(plugin, pluginManager);
                      },
              );
            } else {
              actionButton = OutlinedButton.icon(
                icon: const Icon(Icons.check, color: Colors.green),
                label: const Text('重新覆盖安装'),
                onPressed: anyDownloading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _downloadAndInstall(plugin, pluginManager);
                      },
              );
            }

            Widget contentWidget;
            if (local == null) {
              // 没安装过，显示描述
              contentWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('插件功能描述:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      displayDesc,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // 安装过，显示变更日志
              contentWidget = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('版本变更日志:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: colorScheme.primary
                              .withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      plugin.changelog.isNotEmpty ? plugin.changelog : '暂无变更日志',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  MarketPluginIconWidget(
                      iconString: displayIcon,
                      name: displayName,
                      size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(ctx)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          local != null
                              ? '已安装本地版本: v${local.version}'
                              : '在线最新: v${plugin.version}',
                          style:
                              Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    contentWidget,
                    if (displayTags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('标签:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: displayTags
                            .map((t) => _buildTagBadge(context, t, colorScheme))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '最近更新于: ${plugin.updatedAt.length >= 19 ? plugin.updatedAt.substring(0, 19) : plugin.updatedAt}',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('历史版本'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showOnlineHistoryDialog(context, plugin, pluginManager, local);
                  },
                ),
                actionButton,
              ],
            );
          },
        );
      },
    );
  }

  /// 弹出在线插件历史版本对话框
  void _showOnlineHistoryDialog(
    BuildContext context,
    MarketPlugin plugin,
    PluginManager pluginManager,
    LocalPlugin? local,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = plugin.name.isNotEmpty ? plugin.name : plugin.pluginId;
    final displayDesc = plugin.description.isNotEmpty ? plugin.description : '暂无功能描述。';
    final displayIcon = plugin.icon;

    // 触发预拉取历史版本（若尚未缓存）
    _fetchPluginVersions(plugin.pluginId);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final anyDownloading = _downloadProgress.keys
                .any((k) => k.startsWith('${plugin.pluginId}-'));

            final versions = _versionsCache[plugin.pluginId];
            final isLoadingVersions = _versionsLoading[plugin.pluginId] == true;

            Widget historyListWidget;
            if (isLoadingVersions && versions == null) {
              historyListWidget = const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            } else if (versions == null || versions.isEmpty) {
              historyListWidget = const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无历史版本记录'),
                ),
              );
            } else {
              historyListWidget = Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: versions.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  itemBuilder: (_, i) {
                    final v = versions[i];
                    final vProgressKey = '${v.pluginId}-${v.version}';
                    final vIsDownloading = _downloadProgress.containsKey(vProgressKey);
                    final vProgress = _downloadProgress[vProgressKey] ?? 0.0;
                    final isInstalled = local?.version == v.version;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isInstalled
                              ? Colors.green.withValues(alpha: 0.15)
                              : colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'v${v.version}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isInstalled ? Colors.green : colorScheme.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        v.updatedAt.length >= 10 ? v.updatedAt.substring(0, 10) : v.updatedAt,
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                      subtitle: v.changelog.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                v.changelog,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ),
                            )
                          : null,
                      trailing: vIsDownloading
                          ? SizedBox(
                              width: 60,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      value: vProgress > 0 ? vProgress : null,
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${(vProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(fontSize: 10, color: colorScheme.primary),
                                  ),
                                ],
                              ),
                            )
                          : isInstalled
                              ? Tooltip(
                                  message: '当前已安装',
                                  child: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                )
                              : TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: anyDownloading
                                      ? null
                                      : () {
                                          Navigator.pop(ctx);
                                          _downloadAndInstall(v, pluginManager);
                                        },
                                  child: const Text('安装此版本', style: TextStyle(fontSize: 11)),
                                ),
                    );
                  },
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  MarketPluginIconWidget(
                    iconString: displayIcon,
                    name: displayName,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '历史版本记录',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('插件功能描述:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.maxFinite,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        displayDesc,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.history, size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '历史记录',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    historyListWidget,
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await pluginManager.uninstallPlugin(plugin.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已成功卸载插件 ${plugin.name}'),
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

  Widget _buildTagBadge(BuildContext context, String tag, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
