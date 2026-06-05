import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/tab_manager.dart';
import '../models/app_mode_manager.dart';
import '../models/pool_manager.dart';
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
  /// 键为稳定的 tab.id（String），避免关闭中间 tab 后 index 漂移导致串台
  final Map<String, GlobalKey<PluginWebViewState>> _webViewKeys = {};
  
  /// 缓存标签页组件实例，以 TabItem.id 为键，避免切换时重载
  final Map<String, Widget> _tabCache = {};

  /// 控制台面板尺寸占比（手机为高度比，桌面/平板为宽度比）
  double _consoleSizeFraction = 0.35;

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
    // 使用稳定的 tab.id 而非 index，避免关闭中间 tab 后 index 漂移
    final tabId = tabManager.currentTab.id;
    final state = _webViewKeys[tabId]?.currentState;
    if (state != null) {
      setState(() {
        state.consoleManager.toggleVisibility();
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
      // 捕获当前 controller 引用，在异步回调前检查是否仍是同一个实例
      // 避免 快速关闭 tab -> controller 重建 -> 尚未调用的 animateTo 在已 dispose controller 上执行
      final capturedController = _tabController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController == capturedController) {
          _tabController!.animateTo(tabManager.currentIndex);
        }
      });
    }

    // 清理已不存在的标签页缓存
    final currentTabIds = tabManager.tabs.map((t) => t.id).toSet();
    _tabCache.removeWhere((id, _) => !currentTabIds.contains(id));
    
    // 使用 tab.id 清理 webViewKeys（与 _tabCache 保持一致）
    _webViewKeys.removeWhere((id, _) => !currentTabIds.contains(id));
    
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
      drawer: isStreamMode ? null : _buildDrawer(context, tabManager),
      body: _buildBodyContent(context, tabManager),
      floatingActionButton: isStreamMode
          ? FloatingActionButton(
              onPressed: () => _showCreatePoolDialog(context),
              tooltip: '新建池',
              child: const Icon(Icons.add),
            )
          : _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 中等布局 (平板)
  /// 使用 NavigationRail 侧边导航
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
      floatingActionButton: isStreamMode
          ? FloatingActionButton(
              onPressed: () => _showCreatePoolDialog(context),
              tooltip: '新建池',
              child: const Icon(Icons.add),
            )
          : _buildInstallFAB(context, pluginManager),
    );
  }
  
  /// 大型布局 (桌面)
  /// 使用 MD3 风格的顶部标签栏
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
              onPressed: () => _showCreatePoolDialog(context),
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
  
  /// 构建抽屉菜单 (紧凑布局)
  Widget _buildDrawer(BuildContext context, TabManager tabManager) {
    return Drawer(
      child: Column(
        children: [
          // 顶部安全区域间距
          SizedBox(height: MediaQuery.of(context).padding.top + 8),
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
          // 打开控制台（仅当前 tab 是插件时显示）
          if (tabManager.currentTab.plugin != null)
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('控制台'),
              onTap: () {
                Navigator.pop(context);
                _toggleConsole();
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
    final appModeManager = context.watch<AppModeManager>();
    final isStreamMode = appModeManager.isStreamMode;

    // 始终构建插件内容，不因模式切换而 dispose WebView
    final children = <Widget>[];
    
    for (int i = 0; i < tabManager.tabs.length; i++) {
      final tab = tabManager.tabs[i];
      
      // 从缓存获取或创建组件
      final cachedWidget = _tabCache.putIfAbsent(tab.id, () {
        if (tab.plugin == null) {
          return const MarketView();
        } else {
          return PluginWebView(
            key: _getWebViewKey(tab.id), // 使用稳定的 tab.id
            plugin: tab.plugin!,
          );
        }
      });
      
      children.add(cachedWidget);
    }

    // 获取当前插件 tab 的 ConsoleManager
    final currentIndex = tabManager.currentIndex;
    final currentTabId = tabManager.currentTab.id;
    final currentState = _webViewKeys[currentTabId]?.currentState; // 使用 tab.id
    final consoleManager = currentState?.consoleManager;
    final isConsoleVisible = consoleManager?.isVisible ?? false;

    // 主内容区（WebView / 市场页）
    final mainContent = IndexedStack(
      index: currentIndex,
      children: children,
    );

    // 构建插件内容（含控制台）
    Widget pluginContent;
    if (!isConsoleVisible || consoleManager == null) {
      pluginContent = mainContent;
    } else {
      // 控制台面板
      final consolePanel = ConsolePanel(
        consoleManager: consoleManager,
        webViewController: currentState?.webViewController,
        onClose: () {
          setState(() {
            consoleManager.hide();
          });
        },
      );

      final colorScheme = Theme.of(context).colorScheme;
      final isCompact = ResponsiveHelper.isCompact(context);

      if (isCompact) {
        // ── 手机：上下分栏，控制台在底部 ──
        pluginContent = LayoutBuilder(
          builder: (context, constraints) {
            final totalHeight = constraints.maxHeight;
            final consoleHeight = (totalHeight * _consoleSizeFraction)
                .clamp(_dividerThickness + 80, totalHeight - 80);
            final mainHeight = totalHeight - consoleHeight - _dividerThickness;

            return Column(
              children: [
                SizedBox(height: mainHeight, child: mainContent),
                _buildHorizontalDragHandle(colorScheme, totalHeight),
                SizedBox(height: consoleHeight, child: consolePanel),
              ],
            );
          },
        );
      } else {
        // ── 桌面/平板：左右分栏，控制台在右侧 ──
        pluginContent = LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final consoleWidth = (totalWidth * _consoleSizeFraction)
                .clamp(_dividerThickness + 200, totalWidth - 200);
            final mainWidth = totalWidth - consoleWidth - _dividerThickness;

            return Row(
              children: [
                SizedBox(width: mainWidth, child: mainContent),
                _buildVerticalDragHandle(colorScheme, totalWidth),
                SizedBox(width: consoleWidth, child: consolePanel),
              ],
            );
          },
        );
      }
    }

    // 使用 Offstage 保留 WebView 状态，切换到溯流模式时不 dispose WebView
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

  /// 水平分隔条（手机底部面板，上下拖拽调节高度）
  Widget _buildHorizontalDragHandle(
    ColorScheme colorScheme,
    double totalSize,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        setState(() {
          _consoleSizeFraction -= details.primaryDelta! / totalSize;
          _consoleSizeFraction = _consoleSizeFraction.clamp(
            _minConsoleFraction, _maxConsoleFraction,
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: _dividerThickness,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          child: Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 垂直分隔条（桌面/平板右侧边栏，左右拖拽调节宽度）
  Widget _buildVerticalDragHandle(
    ColorScheme colorScheme,
    double totalSize,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _consoleSizeFraction -= details.primaryDelta! / totalSize;
          _consoleSizeFraction = _consoleSizeFraction.clamp(
            _minConsoleFraction, _maxConsoleFraction,
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: _dividerThickness,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          child: Center(
            child: Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
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
          await pluginManager.installPlugin(
            onConflict: (existingPlugin, newManifest) async {
              if (!context.mounted) return false;
              
              // 显示覆盖确认对话框
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
  /// - 选中且可关闭时，右上角叠加一个 close 角标，单击关闭
  /// - 长按 / 鼠标右键 弹出上下文菜单（关闭 / 关闭其他 / 关闭右侧）
  /// - 用 Tooltip 提示长按可关闭，提升发现性
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
      // 不可关闭（home tab）只需要图标本身
      return iconWidget;
    }

    // 包一层 GestureDetector 提供长按 / 右键菜单
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
    // 是否存在其他可关闭的 tab
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

  /// 显示创建池对话框
  void _showCreatePoolDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建池'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '池名称',
            hintText: '请输入池的名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && ctx.mounted) {
                ctx.read<PoolManager>().createPool(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}
