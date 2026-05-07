import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pool_manager.dart';
import '../models/plugin_manager.dart';
import '../screens/pool_data_management_tab.dart';
import '../screens/plugin_webview.dart';

/// 池详情页面
/// 包含数据管理标签页 + 池内插件标签页
class PoolDetailPage extends StatefulWidget {
  final String poolId;

  const PoolDetailPage({super.key, required this.poolId});

  @override
  State<PoolDetailPage> createState() => _PoolDetailPageState();
}

class _PoolDetailPageState extends State<PoolDetailPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final Map<String, GlobalKey<PluginWebViewState>> _webViewKeys = {};

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  GlobalKey<PluginWebViewState> _getWebViewKey(String poolPluginId) {
    return _webViewKeys.putIfAbsent(
        poolPluginId, () => GlobalKey<PluginWebViewState>());
  }

  TabController _getTabController(int tabCount, int currentIndex) {
    if (_tabController == null || _tabController!.length != tabCount) {
      _tabController?.dispose();
      _tabController = TabController(
        length: tabCount,
        vsync: this,
        initialIndex: currentIndex.clamp(0, tabCount - 1),
      );
    }
    return _tabController!;
  }

  @override
  Widget build(BuildContext context) {
    final poolManager = context.watch<PoolManager>();
    final pluginManager = context.watch<PluginManager>();

    final pool = poolManager.getPoolById(widget.poolId);
    if (pool == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('池不存在')),
        body: const Center(child: Text('该池已被删除')),
      );
    }

    final poolPlugins = poolManager.getPoolPlugins(widget.poolId);

    // Tab: [数据管理, ...plugins]
    final tabCount = 1 + poolPlugins.length;
    final tabController = _getTabController(tabCount, 0);

    // Build local plugins list from pool plugins
    final localPlugins = poolPlugins.map((pp) {
      return pluginManager.plugins
          .cast<LocalPlugin?>()
          .firstWhere((p) => p?.id == pp.pluginId, orElse: () => null);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(pool.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.manage_accounts_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('数据管理'),
                    ],
                  ),
                ),
                ...List.generate(poolPlugins.length, (index) {
                  final localPlugin = localPlugins[index];
                  final name = localPlugin?.name ?? '未知插件';
                  return Tab(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.extension_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          name.length > 12
                              ? '${name.substring(0, 12)}...'
                              : name,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          // Data management tab
          PoolDataManagementTab(poolId: widget.poolId),
          // Plugin tabs (no keep-alive - reload on switch)
          ...List.generate(poolPlugins.length, (index) {
            final pp = poolPlugins[index];
            final localPlugin = localPlugins[index];
            if (localPlugin == null) {
              return Center(
                child: Text('插件 ${pp.pluginId} 未安装'),
              );
            }
            return PluginWebView(
              key: _getWebViewKey(pp.id),
              plugin: localPlugin,
              poolId: widget.poolId,
              poolPluginId: pp.id,
            );
          }),
        ],
      ),
    );
  }
}
