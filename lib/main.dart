import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'theme/theme_provider.dart';
import 'models/database_manager.dart';
import 'models/plugin_manager.dart';
import 'models/plugin_data_manager.dart';
import 'models/tab_manager.dart';
import 'models/window_config_manager.dart';
import 'models/app_mode_manager.dart';
import 'models/pool_manager.dart';
import 'models/variable_pool_manager.dart';
import 'screens/home_page.dart';
import 'widgets/rain_background.dart';
import 'utils/material_icons_registry.dart';

import 'sandbox_server.dart';
import 'plugin_api_server.dart';

// 用于承载插件沙盒文件的本地 HTTP 服务器静态实例
SandboxServer? localhostServer;

// 沙盒服务器实际监听端口（start() 成功后由系统自动分配）
int sandboxServerPort = 0;

// 插件管理 API 服务器实例
PluginApiServer? pluginApiServer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 SQLite 数据库（必须在各 Manager 之前完成）
  await DatabaseManager.instance.init();

  // 预加载 Material Icons codepoints 表（异步且不阻塞 runApp，
  // 但通常会在第一帧渲染前完成；未完成时插件图标会先以缩写兜底，
  // 加载完成后下一次重建即可显示真实图标）
  // 这里 await 是为了大多数情况下首帧就能显示真实图标。
  await MaterialIconsRegistry.instance.ensureInitialized();

  // 如果底层在 Android 上，可能要等待引擎初始化
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  // 启动本地 Http Server 作为沙盒域
  // 注意，documentRoot 设置为 '' 因为我们需要在运行时根据沙盒路径动态定位
  // 更灵活的方式是将其设置为 pluginManager 的 sandboxDir 基础路径
  // 但需要在它初始化完成后启动
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PluginManager()),
        ChangeNotifierProvider(create: (_) => PluginDataManager()),
        ChangeNotifierProvider(create: (_) => TabManager()),
        ChangeNotifierProvider(create: (_) => WindowConfigManager()),
        ChangeNotifierProvider(create: (_) => AppModeManager()),
        ChangeNotifierProvider(create: (_) => PoolManager()),
        ChangeNotifierProvider(create: (_) => VariablePoolManager()),
      ],
      child: const RainCurtainApp(),
    ),
  );
}

class RainCurtainApp extends StatefulWidget {
  const RainCurtainApp({super.key});

  @override
  State<RainCurtainApp> createState() => _RainCurtainAppState();
}

class _RainCurtainAppState extends State<RainCurtainApp> {
  bool _serverStarted = false;
  String? _serverError; // 服务器启动失败时保存错误信息
  PluginManager? _pm;   // 保存引用以便 dispose 时移除监听器

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初始化窗口配置管理器
      final windowConfig = Provider.of<WindowConfigManager>(context, listen: false);
      windowConfig.init();

      _pm = Provider.of<PluginManager>(context, listen: false);
      _pm!.addListener(_checkAndStartServer);
      _checkAndStartServer(); // 立即检查一次
    });
  }

  /// 尝试启动 SandboxServer 和 PluginApiServer
  void _checkAndStartServer() async {
    final pm = _pm;
    // 已成功启动、或已出错（等待用户手动重试）时不重复执行
    if (pm == null || !pm.isInit || _serverStarted || _serverError != null) return;
    try {
      localhostServer = SandboxServer(
        documentRoot: pm.sandboxDir,
      );
      await localhostServer!.start();
      sandboxServerPort = localhostServer!.actualPort;

      // 启动插件管理 API 服务器
      pluginApiServer = PluginApiServer(pm);
      final apiStarted = await pluginApiServer!.start();
      if (apiStarted) {
        debugPrint('Plugin API Server started at http://127.0.0.1:${PluginApiServer.kPort}');
      } else {
        debugPrint('Plugin API Server failed to start (port in use?), external tools will be unavailable');
      }

      if (mounted) {
        setState(() {
          _serverStarted = true;
        });
      }
    } catch (e) {
      debugPrint('[RainCurtain] Server start failed: $e');
      if (mounted) {
        setState(() {
          _serverError = e.toString();
        });
      }
    }
  }

  /// 重试启动服务器（用户点击重试按钮时触发）
  void _retryServer() {
    setState(() {
      _serverError = null;
    });
    _checkAndStartServer();
  }

  @override
  void dispose() {
    _pm?.removeListener(_checkAndStartServer);
    localhostServer?.close();
    pluginApiServer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: '雨幕',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        return RainBackground(
          showRain: themeProvider.showRain,
          angle: themeProvider.rainAngle,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _serverError != null
          ? _buildServerErrorPage()
          : _serverStarted
              ? const HomePage()
              : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }

  /// 服务器启动失败时显示的错误界面
  Widget _buildServerErrorPage() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                '启动失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                _serverError ?? '未知错误',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _retryServer,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
