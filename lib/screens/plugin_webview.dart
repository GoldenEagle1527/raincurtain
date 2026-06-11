import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../models/plugin_manager.dart';
import '../models/console_manager.dart';
import '../models/plugin_storage_manager.dart';
import '../main.dart' show sandboxServerPort;

// 子模块导入
import 'plugin_webview/theme_injector.dart' as theme;
import 'plugin_webview/scroll_fix.dart' as scroll;
import 'plugin_webview/notification_handler.dart';
import 'plugin_webview/clipboard_handler.dart';
import 'plugin_webview/filesystem_handler.dart';
import 'plugin_webview/fetch_handler.dart';
import 'plugin_webview/raincurtain_api_handler.dart';
import 'plugin_webview/ws_handler.dart';
import 'plugin_webview/udp_handler.dart';
import 'plugin_webview/dns_handler.dart';
import 'plugin_webview/orientation_handler.dart';
import 'plugin_webview/console_handler.dart';
import 'plugin_webview/dialog_interceptor.dart';
import '../utils/permission_utils.dart';
import '../utils/responsive_helper.dart';

/// 插件 WebView 视图
/// 加载并显示插件的 Web 内容
class PluginWebView extends StatefulWidget {
  final LocalPlugin plugin;
  /// 溯流模式：所属池 ID（可选，null 表示雨幕模式）
  final String? poolId;
  /// 溯流模式：池内插件配置 ID（可选）
  final String? poolPluginId;

  const PluginWebView({
    super.key,
    required this.plugin,
    this.poolId,
    this.poolPluginId,
  });

  @override
  State<PluginWebView> createState() => PluginWebViewState();
}

class PluginWebViewState extends State<PluginWebView>
    with AutomaticKeepAliveClientMixin,
         NotificationMixin,
         ClipboardMixin,
         FileSystemMixin,
         FetchMixin,
         RainCurtainApiMixin,
         WebSocketMixin,
         UdpMixin,
         DnsMixin,
         OrientationMixin,
         ConsoleMixin,
         DialogMixin {
  @override
  bool get wantKeepAlive => true;

  InAppWebViewController? webViewController;
  double progress = 0;
  bool hasError = false;
  String? errorMessage;
  ThemeData? _currentTheme;
  bool _isDbReady = false;
  late LocalPlugin _currentPlugin;

  /// 控制台日志管理器，用于捕获 WebView 的 console 输出
  final ConsoleManager consoleManager = ConsoleManager();

  /// 是否为手机模式
  bool isMobileMode = false;

  static const String mobileUserAgent = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';
  static const String pcUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36';

  /// 切换设备模式 (手机/电脑模式) 并更改 User Agent 重新加载
  Future<void> toggleDeviceMode() async {
    setState(() {
      isMobileMode = !isMobileMode;
    });
    if (webViewController != null) {
      final settings = await webViewController!.getSettings();
      if (settings != null) {
        settings.userAgent = isMobileMode ? mobileUserAgent : pcUserAgent;
        await webViewController!.setSettings(settings: settings);
        await webViewController!.reload();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _currentPlugin = widget.plugin;
    initNotifications();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    initWsManager(() => webViewController, () => mounted);
    initUdpManager(() => webViewController, () => mounted);
    initDnsManager();
    _ensurePluginStorageSchema();
  }

  Future<void> _ensurePluginStorageSchema() async {
    try {
      final pluginManager = context.read<PluginManager>();
      final updatedPlugin = await pluginManager.reloadPlugin(widget.plugin.id);
      if (updatedPlugin != null && mounted) {
        setState(() {
          _currentPlugin = updatedPlugin;
        });
      }
    } catch (e) {
      debugPrint('Failed to reload plugin before ensuring storage schema: $e');
    }

    final plugin = _currentPlugin;
    final manifest = plugin.manifest;
    if (manifest.storage.isNotEmpty) {
      try {
        final didChange = await PluginStorageManager.instance.ensureTablesForPlugin(
          manifest.id,
          manifest.storage,
        );
        if (didChange && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已自动更新插件“${plugin.name}”的数据库表结构'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Failed to ensure database tables for plugin ${plugin.id}: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isDbReady = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newTheme = Theme.of(context);
    if (_currentTheme != null && _currentTheme != newTheme && webViewController != null) {
      // 主题发生变化，且 webview 已经加载
      webViewController?.evaluateJavascript(source: theme.generateThemeJS(newTheme));
    }
    _currentTheme = newTheme;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    // 取消所有未完成的网络请求，防止 dispose 后回调引发异常
    disposeFetch();
    // 关闭所有 WebSocket 连接和服务端
    disposeWs();
    // 关闭所有 UDP socket
    disposeUdp();
    // 释放 DNS 管理器
    disposeDns();
    // 关闭所有打开的文件写入句柄
    disposeFileSystem();
    // 恢复屏幕方向（如果插件锁定了方向）
    disposeOrientation();
    // 释放 WebView 控制器引用
    webViewController = null;
    // 释放控制台管理器
    consoleManager.dispose();
    super.dispose();
  }

  /// 监听键盘事件，F12 / Ctrl+Shift+I / Ctrl+Shift+J 打开 DevTools
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    final isF12 = key == LogicalKeyboardKey.f12;
    final isCtrlShiftI = ctrl && shift && key == LogicalKeyboardKey.keyI;
    final isCtrlShiftJ = ctrl && shift && key == LogicalKeyboardKey.keyJ;

    if (isF12 || isCtrlShiftI || isCtrlShiftJ) {
      webViewController?.openDevTools();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    
    final plugin = _currentPlugin;
    final manifest = plugin.manifest;
    final needsDb = manifest.storage.isNotEmpty;
    final isReady = !needsDb || _isDbReady;
    
    final colorScheme = Theme.of(context).colorScheme;
    if (!isReady) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 使用系统自动分配的沙盒服务器端口
    final url = 'http://localhost:$sandboxServerPort/${plugin.id}/';

    Widget mainView = Stack(
      children: [
        // WebView 主体
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialUserScripts: UnmodifiableListView([
            // 注入 console 拦截脚本（必须最先注入，以便在插件代码之前拦截）
            UserScript(
              source: ConsoleMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入当前应用的主题色系和基础样式
            UserScript(
              source: theme.generateThemeJS(Theme.of(context)),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 MD3 弹窗组件（alert / confirm / prompt）
            UserScript(
              source: DialogMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
            // Windows 平台不注入通知 polyfill，使用原生 Web Notification API
            if (!Platform.isWindows)
              UserScript(
                source: NotificationMixin.polyfillJS,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            UserScript(
              source: ClipboardMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入文件系统 API polyfill，透明代理 showSaveFilePicker 等
            UserScript(
              source: FileSystemMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 API 脚本
            UserScript(
              source: generateRainCurtainAPI(plugin.id),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入网络请求拦截脚本，跨域请求改由 Flutter 侧发起
            UserScript(
              source: FetchMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 WebSocket API 脚本（RainCurtain.ws）
            UserScript(
              source: WebSocketMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 UDP API 脚本（RainCurtain.udp）
            UserScript(
              source: UdpMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入 DNS API 脚本（RainCurtain.dns）
            UserScript(
              source: DnsMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // 注入屏幕方向控制 API 脚本（RainCurtain.orientation）
            UserScript(
              source: OrientationMixin.polyfillJS,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
            // Windows 平台注入滚动修复脚本，解决 WebView2 滚轮事件问题
            if (Platform.isWindows)
              UserScript(
                source: scroll.scrollFixJS,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
          ]),
          initialSettings: InAppWebViewSettings(
            isInspectable: true,
            transparentBackground: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            javaScriptCanOpenWindowsAutomatically: true,
            // 默认情况下若切换到手机模式，使用手机 UA，否则由系统自行分配（初始化设为 null）
            userAgent: isMobileMode ? mobileUserAgent : null,
            // 地理位置放行
            geolocationEnabled: true,
            // Android 特有：允许混合内容（http 与 https 混用）
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            // Android 特有：允许通用访问（跨域 file:// 等）
            allowUniversalAccessFromFileURLs: true,
            allowFileAccessFromFileURLs: true,
            // 允许内容 URL 访问
            allowContentAccess: true,
            // 允许文件访问
            allowFileAccess: true,
            // 关闭安全浏览（避免拦截本地 localhost 内容）
            safeBrowsingEnabled: false,
            // 允许第三方 Cookie（Android 5+）
            thirdPartyCookiesEnabled: true,
            // 支持 DOM Storage
            domStorageEnabled: true,
            // 数据库存储
            databaseEnabled: true,
          ),
          // Android: 当网页请求麦克风/摄像头等权限时，按需请求原生权限
          onPermissionRequest: (controller, request) async {
            if (!Platform.isAndroid) {
              // 非 Android 平台直接放行
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            }

            final grantedResources =
                await PermissionUtils.requestForWebViewResources(
              request.resources,
            );

            if (grantedResources.isEmpty) {
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY,
              );
            }

            return PermissionResponse(
              resources: grantedResources,
              action: PermissionResponseAction.GRANT,
            );
          },
          // Android: 当网页请求地理位置时，按需请求位置权限
          onGeolocationPermissionsShowPrompt:
              (controller, origin) async {
            final granted =
                await PermissionUtils.requestLocationPermission();
            return GeolocationPermissionShowPromptResponse(
              origin: origin,
              allow: granted,
              retain: granted,
            );
          },
          onJsAlert: handleJsAlert,
          onJsConfirm: handleJsConfirm,
          onJsPrompt: handleJsPrompt,
          onWebViewCreated: (controller) {
            webViewController = controller;

            // 注册各模块 Handler
            registerNotificationHandlers(controller);
            registerClipboardHandlers(controller);
            registerApiHandlers(
              controller,
              context: context,
              plugin: plugin,
              poolId: widget.poolId,
              poolPluginId: widget.poolPluginId,
            );
            registerFetchHandlers(
              controller,
              getWebViewController: () => webViewController,
              isMounted: () => mounted,
            );
            registerDownloadHandler(
              controller,
              context: context,
              isMounted: () => mounted,
            );
            registerFileSystemHandlers(controller);
            registerWsHandlers(controller);
            registerUdpHandlers(controller);
            registerDnsHandlers(controller);
            registerOrientationHandlers(controller);
            registerConsoleHandlers(controller, consoleManager);
          },
          // 拦截下载请求
          onDownloadStartRequest: (controller, downloadRequest) async {
            await handleDownload(
              context: context,
              isMounted: () => mounted,
              url: downloadRequest.url.toString(),
              controller: controller,
              suggestedFilename: downloadRequest.suggestedFilename,
              mimeType: downloadRequest.mimeType,
            );
          },
          onLoadStart: (controller, url) {
            setState(() {
              hasError = false;
              errorMessage = null;
              progress = 0;
            });
          },
          onLoadStop: (controller, url) async {
            setState(() {
              progress = 1.0;
            });
          },
          onProgressChanged: (controller, progress) {
            setState(() {
              this.progress = progress / 100;
            });
          },
          onReceivedError: (controller, request, error) {
            // 忽略 net::ERR_CONNECTION_REFUSED 等由于 SandboxServer 尚未就绪导致的错误
            // 等待一段时间后自动重试
            if (error.description.contains('ERR_CONNECTION_REFUSED')) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && webViewController != null) {
                  webViewController?.reload();
                }
              });
              return;
            }

            // 将网络错误记录到控制台
            consoleManager.addMessage(
              ConsoleLevel.error,
              '${error.description}\n${request.url}',
            );

            setState(() {
              hasError = true;
              errorMessage = error.description;
              progress = 1.0;
            });
          },
          onReceivedHttpError: (controller, request, errorResponse) {
            // 将 HTTP 错误记录到控制台（模拟浏览器 DevTools 的行为）
            final url = request.url.toString();
            final statusCode = errorResponse.statusCode;
            final reasonPhrase = errorResponse.reasonPhrase ?? '';
            consoleManager.addMessage(
              ConsoleLevel.error,
              'Failed to load resource: the server responded with a status of '
              '$statusCode ($reasonPhrase)\n$url',
            );
          },
        ),
        // 进度条
        if (progress < 1.0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.primary,
              ),
              minHeight: 2,
            ),
          ),
        // 错误提示层
        if (hasError)
          Positioned.fill(
            child: Container(
              color: colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '页面加载失败',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colorScheme.error,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorMessage ?? '未知错误',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          hasError = false;
                          errorMessage = null;
                          progress = 0;
                        });
                        webViewController?.reload();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    if (isMobileMode && !ResponsiveHelper.isCompact(context)) {
      mainView = Container(
        color: colorScheme.surfaceContainer,
        child: Center(
          child: Container(
            width: 412,
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: mainView,
          ),
        ),
      );
    }

    return mainView;
  }
}
