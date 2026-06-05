import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart';

import '../models/plugin_manager.dart';
import '../models/plugin_icon.dart';
import '../models/tab_manager.dart';
import '../utils/material_icons_registry.dart';
import '../utils/responsive_helper.dart';
import '../widgets/plugin_icon_widget.dart';

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
  final TextEditingController _searchController = TextEditingController();

  // ── 在线市场状态 ──
  List<MarketPlugin> _marketPlugins = [];
  bool _isLoadingMarket = false;
  String? _marketError;

  bool _isSearchingMarket = false;
  String _searchQueryMarket = '';
  final TextEditingController _searchControllerMarket = TextEditingController();

  // 下载进度跟踪：[pluginId] -> 进度 0.0 ~ 1.0
  final Map<String, double> _downloadProgress = {};

  // manifest 缓存：[pluginId/version] -> ManifestInfo
  final Map<String, ManifestInfo> _manifestCache = {};

  // Worker API 地址（新地址）
  static const String _apiBaseUrl =
      'https://api.raincurtain-pluginmarket.goldeneaglepersonal.de5.net';

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
      final url = query.isNotEmpty
          ? '$_apiBaseUrl/api/plugins?q=${Uri.encodeComponent(query)}'
          : '$_apiBaseUrl/api/plugins';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final jsonMap = json.decode(res.body);
        if (jsonMap['success'] == true) {
          final list = jsonMap['data'] as List;
          setState(() {
            _marketPlugins =
                list.map((x) => MarketPlugin.fromJson(x)).toList();
          });
          // 异步预拉取 manifest 信息
          for (final plugin in _marketPlugins) {
            _fetchManifestInfo(plugin);
          }
        } else {
          throw Exception(jsonMap['error'] ?? '拉取列表失败');
        }
      } else {
        throw Exception('HTTP 服务端响应异常 (${res.statusCode})');
      }
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

  /// 从 manifest_url 异步拉取并缓存 manifest 信息（name/description/author/icon）
  Future<void> _fetchManifestInfo(MarketPlugin plugin) async {
    final cacheKey = '${plugin.pluginId}/${plugin.version}';
    if (_manifestCache.containsKey(cacheKey)) return;

    try {
      final res = await http
          .get(Uri.parse(plugin.manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final yaml = loadYaml(res.body);
        if (yaml is YamlMap) {
          final info = ManifestInfo.fromYaml(yaml);
          if (mounted) {
            setState(() {
              _manifestCache[cacheKey] = info;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[Market] manifest 拉取失败 ($cacheKey): $e');
    }
  }

  /// 获取某个插件的 manifest 缓存（可能为 null，表示还在加载）
  ManifestInfo? _getManifestInfo(MarketPlugin plugin) {
    return _manifestCache['${plugin.pluginId}/${plugin.version}'];
  }

  // 流式下载并调用 PluginManager 一键安装
  Future<void> _downloadAndInstall(
      MarketPlugin plugin, PluginManager pluginManager) async {
    setState(() {
      _downloadProgress[plugin.pluginId] = 0.0;
    });

    // 优先使用 CDN 直链，失败时通过 Worker direct 模式
    final cdnUrl = plugin.downloadUrl;
    final directUrl =
        '$_apiBaseUrl/api/plugins/download/${Uri.encodeComponent(plugin.pluginId)}/${Uri.encodeComponent(plugin.version)}?direct=true';

    debugPrint('[Market] 准备下载插件: "${plugin.pluginId}" v${plugin.version}');
    debugPrint('[Market] 优先尝试 CDN 下载 URL: $cdnUrl');

    try {
      var client = http.Client();
      var request = http.Request('GET', Uri.parse(cdnUrl));
      var response = await client.send(request);

      // 如果 CDN 域名下载失败，则自动尝试 Worker 直连下载通道
      if (response.statusCode != 200) {
        debugPrint('[Market] CDN 下载失败，状态码: ${response.statusCode}');
        debugPrint('[Market] 正在尝试 Worker 直连下载通道: $directUrl');

        client = http.Client();
        request = http.Request('GET', Uri.parse(directUrl));
        response = await client.send(request);

        if (response.statusCode != 200) {
          debugPrint('[Market] 直连下载也失败，状态码: ${response.statusCode}');
          throw Exception('下载请求均告失败 (状态码: ${response.statusCode})');
        } else {
          debugPrint('[Market] 直连通道连接成功，开始流式传输数据...');
        }
      } else {
        debugPrint('[Market] CDN 连接成功，开始流式传输数据...');
      }

      final contentLength = response.contentLength ?? 0;
      List<int> bytes = [];
      int downloaded = 0;

      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          setState(() {
            _downloadProgress[plugin.pluginId] = downloaded / contentLength;
          });
        }
      }

      // 保存至临时文件
      final tempDir = await getTemporaryDirectory();
      final tempFile =
          File(p.join(tempDir.path, '${plugin.pluginId}-${plugin.version}.zip'));
      await tempFile.writeAsBytes(bytes);

      // 调用本地一键解压并注册
      await pluginManager.installPluginFromZip(tempFile, overwrite: true);

      // 清理临时包
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final displayName =
          _getManifestInfo(plugin)?.name ?? plugin.pluginId;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件 "$displayName" 安装成功！'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Market] 下载安装异常: $e');
      final displayName =
          _getManifestInfo(plugin)?.name ?? plugin.pluginId;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件 "$displayName" 安装失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() {
        _downloadProgress.remove(plugin.pluginId);
      });
    }
  }

  /// 根据已安装搜索关键词过滤插件列表
  List<LocalPlugin> _filterPlugins(List<LocalPlugin> plugins) {
    if (_searchQuery.isEmpty) return plugins;
    final query = _searchQuery.toLowerCase();
    return plugins.where((plugin) {
      return plugin.name.toLowerCase().contains(query);
    }).toList();
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
            return IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新列表',
              onPressed: () {
                final tabController = DefaultTabController.of(context);
                if (tabController.index == 0) {
                  pluginManager.reloadPlugins();
                } else {
                  _fetchMarketPlugins(_searchQueryMarket);
                }
              },
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
        const SizedBox(height: 12),
        Expanded(
          child: _isLoadingMarket
              ? const Center(child: CircularProgressIndicator())
              : _marketError != null
                  ? _buildMarketErrorState(context)
                  : _marketPlugins.isEmpty
                      ? _buildOnlineEmptyState(context)
                      : _buildOnlineGrid(
                          context, _marketPlugins, pluginManager, colorScheme),
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

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isNotEmpty
                ? Icons.search_off
                : Icons.inbox_outlined,
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
            _searchQuery.isNotEmpty ? '尝试使用其他关键词搜索' : '点击右下角按钮安装新插件',
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQueryMarket.isNotEmpty
                ? Icons.search_off
                : Icons.cloud_queue_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQueryMarket.isNotEmpty
                ? '未找到符合条件的在线插件'
                : '在线插件市场暂无内容',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQueryMarket.isNotEmpty ? '尝试更换搜索词重新查询' : '点击右上角刷新，或稍后再试',
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
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = ResponsiveHelper.isCompact(context);

    if (isCompact) {
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
          return _buildOnlineCompactCard(
              context, plugin, pluginManager, colorScheme);
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
        return _buildOnlineDesktopCard(
            context, plugin, pluginManager, colorScheme);
      },
    );
  }

  /// 桌面端已安装卡片 (保留原有风格)
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
          Provider.of<TabManager>(context, listen: false)
              .openOrSwitchTab(plugin);
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PluginIconWidget(plugin: plugin),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plugin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  Theme.of(context).textTheme.titleSmall?.copyWith(
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
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
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
                  Text(
                    'v${plugin.version} · ${plugin.author}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
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
                  onPressed: () =>
                      _showUninstallDialog(context, plugin, pluginManager),
                  tooltip: '卸载',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 桌面端在线卡片 (采用相同风格，带状态指示动作按钮)
  Widget _buildOnlineDesktopCard(
    BuildContext context,
    MarketPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    final manifestInfo = _getManifestInfo(plugin);
    // 用 plugin_id（UUID）匹配本地已安装插件
    final local = pluginManager.getPluginById(plugin.pluginId);
    final isDownloading = _downloadProgress.containsKey(plugin.pluginId);

    final displayName = manifestInfo?.name ?? plugin.pluginId;
    final displayDesc = manifestInfo?.description ?? '正在加载插件信息...';

    Widget actionIcon;
    if (isDownloading) {
      final progress = _downloadProgress[plugin.pluginId] ?? 0.0;
      actionIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2,
        ),
      );
    } else if (local == null) {
      actionIcon = Icon(Icons.download, size: 14, color: colorScheme.primary);
    } else if (local.version != plugin.version) {
      actionIcon =
          Icon(Icons.system_update_alt, size: 14, color: colorScheme.secondary);
    } else {
      actionIcon = const Icon(Icons.check, size: 14, color: Colors.green);
    }

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
        onTap: isDownloading
            ? null
            : () => _showOnlineDetailDialog(
                context, plugin, pluginManager, local, manifestInfo),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarketPluginIconWidget(
                          iconString: manifestInfo?.icon, name: displayName),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayDesc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'v${plugin.version}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          height: 1.0,
                        ),
                      ),
                      if (isDownloading)
                        Text(
                          '下载中: ${(_downloadProgress[plugin.pluginId]! * 100).toStringAsFixed(0)}%',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: actionIcon,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 手机端已安装卡片 (保留原有风格)
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
          Provider.of<TabManager>(context, listen: false)
              .openOrSwitchTab(plugin);
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
                  onPressed: () =>
                      _showUninstallDialog(context, plugin, pluginManager),
                  tooltip: '卸载',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 手机端在线卡片 (采用相同风格)
  Widget _buildOnlineCompactCard(
    BuildContext context,
    MarketPlugin plugin,
    PluginManager pluginManager,
    ColorScheme colorScheme,
  ) {
    final manifestInfo = _getManifestInfo(plugin);
    final local = pluginManager.getPluginById(plugin.pluginId);
    final isDownloading = _downloadProgress.containsKey(plugin.pluginId);

    final displayName = manifestInfo?.name ?? plugin.pluginId;
    final displayDesc = manifestInfo?.description ?? '正在加载插件信息...';

    Widget actionIcon;
    if (isDownloading) {
      final progress = _downloadProgress[plugin.pluginId] ?? 0.0;
      actionIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress : null,
          strokeWidth: 2,
        ),
      );
    } else if (local == null) {
      actionIcon = Icon(Icons.download, size: 14, color: colorScheme.primary);
    } else if (local.version != plugin.version) {
      actionIcon =
          Icon(Icons.system_update_alt, size: 14, color: colorScheme.secondary);
    } else {
      actionIcon = const Icon(Icons.check, size: 14, color: Colors.green);
    }

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
        onTap: isDownloading
            ? null
            : () => _showOnlineDetailDialog(
                context, plugin, pluginManager, local, manifestInfo),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MarketPluginIconWidget(
                  iconString: manifestInfo?.icon, name: displayName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
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
                      displayDesc,
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
              if (isDownloading) ...[
                Text(
                  '${(_downloadProgress[plugin.pluginId]! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: actionIcon,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出在线插件详情对话框 (极具排版美感，一键安装/更新/覆盖)
  void _showOnlineDetailDialog(
    BuildContext context,
    MarketPlugin plugin,
    PluginManager pluginManager,
    LocalPlugin? local,
    ManifestInfo? manifestInfo,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = manifestInfo?.name ?? plugin.pluginId;
    final displayDesc = manifestInfo?.description ?? '暂无描述信息。';
    final displayAuthor = manifestInfo?.author ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDownloading =
                _downloadProgress.containsKey(plugin.pluginId);
            final progress = _downloadProgress[plugin.pluginId] ?? 0.0;

            Widget actionButton;
            if (isDownloading) {
              actionButton = OutlinedButton.icon(
                icon: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                label: Text('正在下载 (${(progress * 100).toStringAsFixed(0)}%)'),
                onPressed: null,
              );
            } else if (local == null) {
              actionButton = FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('下载并安装'),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadAndInstall(plugin, pluginManager);
                },
              );
            } else if (local.version != plugin.version) {
              actionButton = FilledButton.icon(
                icon: const Icon(Icons.update),
                label: Text('升级到 v${plugin.version}'),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadAndInstall(plugin, pluginManager);
                },
              );
            } else {
              actionButton = OutlinedButton.icon(
                icon: const Icon(Icons.check, color: Colors.green),
                label: const Text('重新覆盖安装'),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadAndInstall(plugin, pluginManager);
                },
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  MarketPluginIconWidget(
                      iconString: manifestInfo?.icon,
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
                          style: Theme.of(context)
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
                              : '在线版本: v${plugin.version}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (displayAuthor.isNotEmpty)
                    Text(
                      '作者: $displayAuthor',
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  if (displayAuthor.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    '最近更新于: ${plugin.updatedAt.length >= 19 ? plugin.updatedAt.substring(0, 19) : plugin.updatedAt}',
                    style: TextStyle(
                        fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                actionButton,
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
}

// ──────────────────────────────────────────────────────────────────────────────
// 在线插件图标组件（支持 manifest 中的 material:iconName 格式图标）
// ──────────────────────────────────────────────────────────────────────────────

/// 专为在线卡片绘制的图标组件
/// - 若 iconString 为 "material:xxx" 格式，渲染对应 Material Icon
/// - 否则显示插件名称首字作为兜底
class MarketPluginIconWidget extends StatelessWidget {
  final String? iconString;
  final String name;
  final double size;

  const MarketPluginIconWidget({
    super.key,
    required this.iconString,
    required this.name,
    this.size = 32.0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size + 16,
      height: size + 16,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: _buildIconContent(colorScheme),
      ),
    );
  }

  Widget _buildIconContent(ColorScheme colorScheme) {
    // 解析 "material:icon_name" 格式
    if (iconString != null && iconString!.startsWith('material:')) {
      final iconName = iconString!.substring('material:'.length).trim();
      return _buildMaterialIcon(iconName, colorScheme);
    }

    // 兜底：首字缩写
    return _buildAbbreviation(colorScheme);
  }

  Widget _buildMaterialIcon(String iconName, ColorScheme colorScheme) {
    final registry = MaterialIconsRegistry.instance;
    final codePoint =
        registry.lookup(iconName, MaterialIconVariant.filled);

    if (codePoint == null) {
      return _buildAbbreviation(colorScheme);
    }

    return Text(
      String.fromCharCode(codePoint),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontFamily: 'MaterialIcons',
        fontSize: size,
        height: 1.0,
        color: colorScheme.onPrimaryContainer,
        fontFamilyFallback: const <String>[],
      ),
    );
  }

  Widget _buildAbbreviation(ColorScheme colorScheme) {
    final abbr = name
        .substring(0, name.length > 2 ? 2 : name.length)
        .toUpperCase();
    return Text(
      abbr,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: size * 0.5,
        color: colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
        fontFamily: 'NotoSerifSC',
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 数据模型
// ──────────────────────────────────────────────────────────────────────────────

/// 从插件市场 API 返回的在线插件实体（仅包含 API 直接返回的字段）
/// name/description/icon/author 需从 manifestUrl 单独拉取
class MarketPlugin {
  final String pluginId;
  final String version;
  final String updatedAt;
  final String downloadUrl;
  final String manifestUrl;

  const MarketPlugin({
    required this.pluginId,
    required this.version,
    required this.updatedAt,
    required this.downloadUrl,
    required this.manifestUrl,
  });

  factory MarketPlugin.fromJson(Map<String, dynamic> json) {
    return MarketPlugin(
      pluginId: (json['plugin_id'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? '').toString(),
      manifestUrl: (json['manifest_url'] ?? '').toString(),
    );
  }
}

/// 从 manifest_url 拉取并解析得到的附加信息
class ManifestInfo {
  final String name;
  final String description;
  final String author;
  final String? icon; // 例如 "material:groups"

  const ManifestInfo({
    required this.name,
    required this.description,
    required this.author,
    this.icon,
  });

  factory ManifestInfo.fromYaml(YamlMap yaml) {
    return ManifestInfo(
      name: (yaml['name'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      author: (yaml['author'] ?? '').toString(),
      icon: yaml['icon']?.toString(),
    );
  }
}
