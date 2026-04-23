import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/tab_manager.dart';
import '../utils/responsive_helper.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/closeable_tab.dart';
import 'market_view.dart';
import 'plugin_webview.dart';
import 'settings_page.dart';

/// 主页面
/// 根据屏幕尺寸自动切换布局模式:
/// - Compact: 使用 Drawer 抽屉菜单
/// - Medium/Expanded: 使用 NavigationRail 侧边导航
/// - Large/ExtraLarge: 使用顶部标签栏 (MD3 风格)
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  TabController? _tabController;
  /// 每个 tab index 对应的 PluginWebView GlobalKey，用于调用 openDevTools
  final Map<int, GlobalKey<PluginWebViewState>> _webViewKeys = {};
  
  /// 缓存标签页组件实例，以 TabItem.id 为键，避免切换时重载
  final Map<String, Widget> _tabCache = {};
  
  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// 获取或创建指定 tab index 的 GlobalKey
  GlobalKey<PluginWebViewState> _getWebViewKey(int index) {
    return _webViewKeys.putIfAbsent(index, () => GlobalKey<PluginWebViewState>());
  }

  /// 打开当前插件 tab 的 DevTools
  void _openCurrentDevTools() {
    // Android 平台不支持 openDevTools()，引导用户使用 Chrome 远程调试
    if (Platform.isAndroid) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.bug_report_outlined),
          title: const Text('开发者调试'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Android WebView 不支持直接打开 DevTools。\n\n请通过以下步骤使用 Chrome 远程调试：'),
              SizedBox(height: 12),
              Text('1. 用 USB 连接手机到电脑'),
              Text('2. 开启手机的 USB 调试'),
              Text('3. 在电脑 Chrome 浏览器中访问：'),
              SizedBox(height: 4),
              SelectableText(
                'chrome://inspect/#devices',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              SizedBox(height: 4),
              Text('4. 在列表中找到对应 WebView 并点击 inspect'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final tabManager = context.read<TabManager>();
    final index = tabManager.currentIndex;
    _webViewKeys[index]?.currentState?.openDevTools();
  }
  
  /// 获取或创建 TabController
  TabController _getTabController(TabManager tabManager) {
    if (_tabController == null || _tabController!.length != tabManager.tabs.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: tabManager.tabs.length,
        vsync: this,
        initialIndex: tabManager.currentIndex,
      );
      
      // 监听 TabController 变化，同步到 TabManager
      _tabController!.addListener(() {
        if (_tabController!.indexIsChanging) return;
        final tabManager = context.read<TabManager>();
        if (_tabController!.index != tabManager.currentIndex) {
          tabManager.switchToTab(_tabController!.index);
        }
      });
    }
    
    // 同步当前索引
    if (_tabController!.index != tabManager.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController != null) {
          _tabController!.animateTo(tabManager.currentIndex);
        }
      });
    }

    // 清理已不再存在的标签页缓存
    final currentTabIds = tabManager.tabs.map((t) => t.id).toSet();
    _tabCache.removeWhere((id, _) => !currentTabIds.contains(id));
    
    // 清理 webViewKeys (注意：webViewKeys 使用 index 作为键，由于顺序可能变化，这里需要更严谨的处理，
    // 但在当前代码中 index 是由 build 时的循环产生的，所以清理无效内存即可)
    final validIndices = List.generate(tabManager.tabs.length, (i) => i).toSet();
    _webViewKeys.removeWhere((index, _) => !validIndices.contains(index));
    
    return _tabController!;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TabManager>(
      builder: (context, tabManager, child) {
        // 根据屏幕尺寸选择布局
        if (ResponsiveHelper.shouldUseDrawer(context)) {
          return _buildCompactLayout(context, tabManager);
        } else if (ResponsiveHelper.shouldUseNavigationRail(context)) {
          return _buildMediumLayout(context, tabManager);
        } else {
          return _buildLargeLayout(context, tabManager);
        }
      },
    );
  }
  
  /// 紧凑型布局 (手机竖屏)
  /// 使用 Drawer 抽屉菜单
  Widget _buildCompactLayout(BuildContext context, TabManager tabManager) {
    final currentTab = tabManager.currentTab;
    final pluginManager = context.read<PluginManager>();
    final isPlugin = currentTab.plugin != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(currentTab.title),
        actions: [
          if (isPlugin)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: '打开开发者控制台',
              onPressed: _openCurrentDevTools,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, tabManager),
      body: _buildBodyContent(context, tabManager),
      floatingActionButton: _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 中等布局 (平板)
  /// 使用 NavigationRail 侧边导航
  Widget _buildMediumLayout(BuildContext context, TabManager tabManager) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTab = tabManager.currentTab;
    final pluginManager = context.read<PluginManager>();
    final isPlugin = currentTab.plugin != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(currentTab.title),
        actions: [
          if (isPlugin)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: '打开开发者控制台',
              onPressed: _openCurrentDevTools,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // NavigationRail 侧边导航
          NavigationRail(
            selectedIndex: tabManager.currentIndex,
            onDestinationSelected: tabManager.switchToTab,
            labelType: NavigationRailLabelType.all,
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ThemeToggleIconButton(),
                ),
              ),
            ),
            destinations: tabManager.tabs.map((tab) {
              return NavigationRailDestination(
                icon: Icon(tab.plugin == null ? Icons.store_outlined : Icons.extension_outlined),
                selectedIcon: Icon(tab.plugin == null ? Icons.store : Icons.extension),
                label: Text(_truncateTitle(tab.title, 10)),
              );
            }).toList(),
          ),
          // 垂直分割线
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: colorScheme.outlineVariant,
          ),
          // 主内容区域
          Expanded(
            child: _buildBodyContent(context, tabManager),
          ),
        ],
      ),
      floatingActionButton: _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 大型布局 (桌面)
  /// 使用 MD3 风格的顶部标签栏
  Widget _buildLargeLayout(BuildContext context, TabManager tabManager) {
    final pluginManager = context.read<PluginManager>();
    final tabController = _getTabController(tabManager);
    final isPlugin = tabManager.currentTab.plugin != null;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('RainCurtain Plugin OS'),
        actions: [
          if (isPlugin)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: '打开开发者控制台',
              onPressed: _openCurrentDevTools,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsPage(),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: List.generate(tabManager.tabs.length, (index) {
                final tab = tabManager.tabs[index];
                return Tab(
                  height: 36,
                  child: CloseableTab(
                    icon: tab.plugin == null ? Icons.store : Icons.extension,
                    text: tab.title,
                    showCloseButton: tab.plugin != null,
                    onClose: tab.plugin != null
                        ? () => tabManager.closeTab(index)
                        : null,
                    maxTextLength: 15,
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: _buildBodyContent(context, tabManager),
      floatingActionButton: _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 构建抽屉菜单 (紧凑布局)
  Widget _buildDrawer(BuildContext context, TabManager tabManager) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Drawer(
      child: Column(
        children: [
          // 抽屉头部
          SizedBox(
            width: double.infinity,
            child: DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.extension,
                    size: 48,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'RainCurtain',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已打开 ${tabManager.tabs.length} 个标签',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 标签列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tabManager.tabs.length,
              itemBuilder: (context, index) {
                final tab = tabManager.tabs[index];
                final isSelected = tabManager.currentIndex == index;
                
                return ListTile(
                  selected: isSelected,
                  leading: Icon(
                    tab.plugin == null ? Icons.store : Icons.extension,
                  ),
                  title: Text(tab.title),
                  subtitle: tab.plugin == null
                      ? const Text('插件市场')
                      : Text(
                          '${tab.plugin!.author} · v${tab.plugin!.version}\n${tab.plugin!.description}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  isThreeLine: tab.plugin != null,
                  trailing: tab.plugin != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          iconSize: 20,
                          onPressed: () {
                            tabManager.closeTab(index);
                            Navigator.pop(context);
                          },
                          tooltip: '关闭',
                        )
                      : null,
                  onTap: () {
                    tabManager.switchToTab(index);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          // 分割线
          const Divider(),
          // 打开开发者控制台（仅当前 tab 是插件时显示）
          if (tabManager.currentTab.plugin != null)
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('打开开发者控制台'),
              onTap: () {
                Navigator.pop(context);
                _openCurrentDevTools();
              },
            ),
          // 主题切换分段按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: ThemeToggleSegmentedButton(),
          ),
        ],
      ),
    );
  }
  
  /// 构建主内容区域
  Widget _buildBodyContent(BuildContext context, TabManager tabManager) {
    // 根据当前标签页列表构建 IndexedStack 的 children
    final children = <Widget>[];
    
    for (int i = 0; i < tabManager.tabs.length; i++) {
      final tab = tabManager.tabs[i];
      
      // 从缓存获取或创建组件
      final cachedWidget = _tabCache.putIfAbsent(tab.id, () {
        if (tab.plugin == null) {
          return const MarketView();
        } else {
          return PluginWebView(
            key: _getWebViewKey(i),
            plugin: tab.plugin!,
          );
        }
      });
      
      children.add(cachedWidget);
    }

    return IndexedStack(
      index: tabManager.currentIndex,
      children: children,
    );
  }
  
  /// 构建安装插件的浮动按钮（仅在市场页面显示）
  Widget? _buildInstallFAB(BuildContext context, PluginManager pluginManager) {
    // 当前 tab 是插件页面时，隐藏安装按钮
    final tabManager = context.read<TabManager>();
    if (tabManager.currentTab.plugin != null) return null;

    return FloatingActionButton(
      onPressed: () async {
        try {
          await pluginManager.installPlugin();
        } catch (e) {
          if (!context.mounted) return;
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('安装失败: $e'),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      },
      tooltip: '安装新插件',
      child: const Icon(Icons.add),
    );
  }
  
  /// 截断标题文字
  String _truncateTitle(String title, int maxLength) {
    if (title.length <= maxLength) return title;
    return '${title.substring(0, maxLength)}...';
  }
}
