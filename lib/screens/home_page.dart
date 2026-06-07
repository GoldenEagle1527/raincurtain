import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/tab_manager.dart';
import '../models/app_mode_manager.dart';
import '../models/s3_config_manager.dart';
import '../models/update_manager.dart';
import '../widgets/update_dialog.dart';
import '../utils/responsive_helper.dart';
import '../widgets/theme_toggle_button.dart';
import '../widgets/closeable_tab.dart';
import '../widgets/plugin_overwrite_dialog.dart';
import '../widgets/console_panel.dart';
import 'market_view.dart';
import 'plugin_webview.dart';
import 'settings_page.dart';
import 'stream_view.dart';

// 导入拆分组件
import 'components/split_pane.dart';
import 'components/home_drawer.dart';
import 'dialogs/create_pool_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoCheckForUpdates();
    });
  }

  void _autoCheckForUpdates() async {
    final configManager = context.read<S3ConfigManager>();
    if (!configManager.isInit) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
    }

    final config = configManager.config;
    if (config == null || config.publicUrl.isEmpty) return;

    final updateManager = context.read<UpdateManager>();
    await updateManager.checkForUpdates(config);

    if (!mounted) return;

    if (updateManager.status == UpdateStatus.hasUpdate) {
      final isSkipped = await updateManager.isUpdateSkipped(
        updateManager.latestVersion ?? '',
        updateManager.latestBuildNumber ?? 0,
      );
      if (!mounted) return;
      if (!isSkipped) {
        showUpdateDialog(context, updateManager, config);
      }
    }
  }

  /// 每个 tab.id 对应的 PluginWebView GlobalKey，用于访问 consoleManager
  final Map<String, GlobalKey<PluginWebViewState>> _webViewKeys = {};
  
  /// 缓存标签页组件实例，以 TabItem.id 为键，避免切换时重载
  final Map<String, Widget> _tabCache = {};

  /// 控制台面板尺寸占比
  final double _consoleSizeFraction = 0.35;

  /// 拖拽分隔条的粗细
  static const double _dividerThickness = 6.0;

  /// 控制台最小/最大尺寸占比
  static const double _minConsoleFraction = 0.15;
  static const double _maxConsoleFraction = 0.70;
  
  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// 获取或创建指定 tab.id 的 GlobalKey
  GlobalKey<PluginWebViewState> _getWebViewKey(String tabId) {
    return _webViewKeys.putIfAbsent(tabId, () => GlobalKey<PluginWebViewState>());
  }

  /// 切换当前插件 tab 的控制台面板显隐
  void _toggleConsole() {
    final tabManager = context.read<TabManager>();
    final currentTabId = tabManager.currentTab.id;
    final currentState = _webViewKeys[currentTabId]?.currentState;
    final consoleManager = currentState?.consoleManager;
    if (consoleManager != null) {
      setState(() {
        consoleManager.toggleVisibility();
      });
    }
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
      
      _tabController!.addListener(() {
        if (_tabController!.indexIsChanging) return;
        final tabManager = context.read<TabManager>();
        if (_tabController!.index != tabManager.currentIndex) {
          tabManager.switchToTab(_tabController!.index);
        }
      });
    }
    
    if (_tabController!.index != tabManager.currentIndex) {
      final capturedController = _tabController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController == capturedController) {
          _tabController!.animateTo(tabManager.currentIndex);
        }
      });
    }

    final currentTabIds = tabManager.tabs.map((t) => t.id).toSet();
    _tabCache.removeWhere((id, _) => !currentTabIds.contains(id));
    _webViewKeys.removeWhere((id, _) => !currentTabIds.contains(id));
    
    return _tabController!;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TabManager>(
      builder: (context, tabManager, child) {
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
  Widget _buildCompactLayout(BuildContext context, TabManager tabManager) {
    final currentTab = tabManager.currentTab;
    final pluginManager = context.read<PluginManager>();
    final appModeManager = context.watch<AppModeManager>();
    final isPlugin = currentTab.plugin != null;
    final isStreamMode = appModeManager.isStreamMode;
    
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => appModeManager.switchMode(),
          child: Tooltip(
            message: isStreamMode ? '点击切换到雨幕模式' : '点击切换到溯流模式',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isStreamMode ? '溯流' : '雨幕'),
                const SizedBox(width: 4),
                Icon(
                  isStreamMode ? Icons.water_outlined : Icons.cloudy_snowing,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isStreamMode && isPlugin)
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: '控制台',
              onPressed: _toggleConsole,
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: context.watch<UpdateManager>().status == UpdateStatus.hasUpdate,
              child: const Icon(Icons.settings),
            ),
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
      drawer: isStreamMode ? null : HomeDrawer(onConsoleTap: _toggleConsole),
      body: _buildBodyContent(context, tabManager),
      floatingActionButton: isStreamMode
          ? FloatingActionButton(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CreatePoolDialog(),
              ),
              tooltip: '新建池',
              child: const Icon(Icons.add),
            )
          : _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 中等布局 (平板)
  Widget _buildMediumLayout(BuildContext context, TabManager tabManager) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTab = tabManager.currentTab;
    final pluginManager = context.read<PluginManager>();
    final appModeManager = context.watch<AppModeManager>();
    final isPlugin = currentTab.plugin != null;
    final isStreamMode = appModeManager.isStreamMode;
    
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => appModeManager.switchMode(),
          child: Tooltip(
            message: isStreamMode ? '点击切换到雨幕模式' : '点击切换到溯流模式',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isStreamMode ? '溯流' : '雨幕'),
                const SizedBox(width: 4),
                Icon(
                  isStreamMode ? Icons.water_outlined : Icons.cloudy_snowing,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isStreamMode && isPlugin)
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: '控制台',
              onPressed: _toggleConsole,
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: context.watch<UpdateManager>().status == UpdateStatus.hasUpdate,
              child: const Icon(Icons.settings),
            ),
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
      body: isStreamMode
          ? _buildBodyContent(context, tabManager)
          : Row(
              children: [
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
                  destinations: List.generate(tabManager.tabs.length, (index) {
                    final tab = tabManager.tabs[index];
                    final canClose = tab.plugin != null;
                    return NavigationRailDestination(
                      icon: _buildRailTabIcon(
                        context: context,
                        tabManager: tabManager,
                        index: index,
                        tab: tab,
                        isSelected: false,
                        canClose: canClose,
                      ),
                      selectedIcon: _buildRailTabIcon(
                        context: context,
                        tabManager: tabManager,
                        index: index,
                        tab: tab,
                        isSelected: true,
                        canClose: canClose,
                      ),
                      label: Text(_truncateTitle(tab.title, 10)),
                    );
                  }),
                ),
                VerticalDivider(
                  thickness: 1,
                  width: 1,
                  color: colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _buildBodyContent(context, tabManager),
                ),
              ],
            ),
      floatingActionButton: isStreamMode
          ? FloatingActionButton(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CreatePoolDialog(),
              ),
              tooltip: '新建池',
              child: const Icon(Icons.add),
            )
          : _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 大型布局 (桌面)
  Widget _buildLargeLayout(BuildContext context, TabManager tabManager) {
    final pluginManager = context.read<PluginManager>();
    final appModeManager = context.watch<AppModeManager>();
    final tabController = _getTabController(tabManager);
    final isPlugin = tabManager.currentTab.plugin != null;
    final isStreamMode = appModeManager.isStreamMode;
    
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => appModeManager.switchMode(),
          child: Tooltip(
            message: isStreamMode ? '点击切换到雨幕模式' : '点击切换到溯流模式',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isStreamMode ? '溯流' : '雨幕'),
                const SizedBox(width: 4),
                Icon(
                  isStreamMode ? Icons.water_outlined : Icons.cloudy_snowing,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!isStreamMode && isPlugin)
            IconButton(
              icon: const Icon(Icons.terminal),
              tooltip: '控制台',
              onPressed: _toggleConsole,
            ),
          if (isStreamMode)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建池',
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CreatePoolDialog(),
              ),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: context.watch<UpdateManager>().status == UpdateStatus.hasUpdate,
              child: const Icon(Icons.settings),
            ),
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
        bottom: isStreamMode
            ? null
            : PreferredSize(
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
                          icon: tab.plugin == null
                              ? Icons.store
                              : Icons.extension,
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
      floatingActionButton: isStreamMode
          ? null
          : _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 构建主内容区域
  Widget _buildBodyContent(BuildContext context, TabManager tabManager) {
    final appModeManager = context.watch<AppModeManager>();
    final isStreamMode = appModeManager.isStreamMode;

    final children = <Widget>[];
    
    for (int i = 0; i < tabManager.tabs.length; i++) {
      final tab = tabManager.tabs[i];
      
      final cachedWidget = _tabCache.putIfAbsent(tab.id, () {
        if (tab.plugin == null) {
          return const MarketView();
        } else {
          return PluginWebView(
            key: _getWebViewKey(tab.id),
            plugin: tab.plugin!,
          );
        }
      });
      
      children.add(cachedWidget);
    }

    final currentIndex = tabManager.currentIndex;
    final currentTabId = tabManager.currentTab.id;
    final currentState = _webViewKeys[currentTabId]?.currentState;
    final consoleManager = currentState?.consoleManager;
    final isConsoleVisible = consoleManager?.isVisible ?? false;

    final mainContent = IndexedStack(
      index: currentIndex,
      children: children,
    );

    Widget pluginContent;
    if (!isConsoleVisible || consoleManager == null) {
      pluginContent = mainContent;
    } else {
      final consolePanel = ConsolePanel(
        consoleManager: consoleManager,
        webViewController: currentState?.webViewController,
        onClose: () {
          setState(() {
            consoleManager.hide();
          });
        },
      );

      final isCompact = ResponsiveHelper.isCompact(context);

      pluginContent = SplitPane(
        mainContent: mainContent,
        secondaryContent: consolePanel,
        isVertical: isCompact,
        initialFraction: _consoleSizeFraction,
        dividerThickness: _dividerThickness,
        minFraction: _minConsoleFraction,
        maxFraction: _maxConsoleFraction,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: isStreamMode,
          child: pluginContent,
        ),
        if (isStreamMode) const StreamView(),
      ],
    );
  }
  
  /// 构建安装插件的浮动按钮
  Widget? _buildInstallFAB(BuildContext context, PluginManager pluginManager) {
    final tabManager = context.read<TabManager>();
    if (tabManager.currentTab.plugin != null) return null;

    return FloatingActionButton(
      onPressed: () async {
        try {
          await pluginManager.installPlugin(
            onConflict: (existingPlugin, newManifest) async {
              if (!context.mounted) return false;
              
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => PluginOverwriteDialog(
                  existingPlugin: existingPlugin,
                  newManifest: newManifest,
                ),
              );
              
              return confirmed ?? false;
            },
          );
          
          if (!context.mounted) return;
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('插件安装成功'),
              backgroundColor: colorScheme.primary,
            ),
          );
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

  /// 构建平板 NavigationRail 上单个 tab 的图标
  Widget _buildRailTabIcon({
    required BuildContext context,
    required TabManager tabManager,
    required int index,
    required TabItem tab,
    required bool isSelected,
    required bool canClose,
  }) {
    final iconData = tab.plugin == null
        ? (isSelected ? Icons.store : Icons.store_outlined)
        : (isSelected ? Icons.extension : Icons.extension_outlined);

    Widget iconWidget = Icon(iconData);

    if (!canClose) {
      return iconWidget;
    }

    final wrapped = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => _showTabContextMenu(
        context: context,
        tabManager: tabManager,
        index: index,
        globalPosition: details.globalPosition,
      ),
      onSecondaryTapDown: (details) => _showTabContextMenu(
        context: context,
        tabManager: tabManager,
        index: index,
        globalPosition: details.globalPosition,
      ),
      child: iconWidget,
    );

    return Tooltip(
      message: '长按 / 右键 可关闭',
      waitDuration: const Duration(milliseconds: 600),
      child: wrapped,
    );
  }

  /// 弹出 tab 上下文菜单
  Future<void> _showTabContextMenu({
    required BuildContext context,
    required TabManager tabManager,
    required int index,
    required Offset globalPosition,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasRight = index < tabManager.tabs.length - 1;
    final hasOthers = tabManager.tabs
        .asMap()
        .entries
        .any((e) => e.key != index && e.value.plugin != null);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'close',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.close),
            title: Text('关闭标签页'),
          ),
        ),
        if (hasOthers)
          const PopupMenuItem<String>(
            value: 'close_others',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.clear_all),
              title: Text('关闭其他标签页'),
            ),
          ),
        if (hasRight)
          const PopupMenuItem<String>(
            value: 'close_right',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.last_page),
              title: Text('关闭右侧所有'),
            ),
          ),
      ],
    );

    if (selected == null) return;
    switch (selected) {
      case 'close':
        tabManager.closeTab(index);
        break;
      case 'close_others':
        tabManager.closeOtherTabs(index);
        break;
      case 'close_right':
        tabManager.closeTabsToRight(index);
        break;
    }
  }
}
