import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'theme/theme_provider.dart';
import 'models/plugin_manager.dart';
import 'models/plugin_data_manager.dart';
import 'models/tab_manager.dart';
import 'models/window_config_manager.dart';
import 'screens/home_page.dart';
import 'widgets/rain_background.dart';

import 'sandbox_server.dart';

// 用于承载插件沙盒文件的本地 HTTP 服务器静态实例
SandboxServer? localhostServer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初始化窗口配置管理器
      final windowConfig = Provider.of<WindowConfigManager>(context, listen: false);
      windowConfig.init();

      final pm = Provider.of<PluginManager>(context, listen: false);
      
      void checkAndStartServer() async {
        if (pm.isInit && !_serverStarted) {
          localhostServer = SandboxServer(
            port: 8080,
            documentRoot: pm.sandboxDir,
          );
          await localhostServer!.start();
          if (mounted) {
            setState(() {
              _serverStarted = true;
            });
          }
        }
      }

      pm.addListener(checkAndStartServer);
      checkAndStartServer(); // 也顺便立刻检查一次
    });
  }

  @override
  void dispose() {
    localhostServer?.close();
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
      home: _serverStarted
          ? const HomePage()
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
