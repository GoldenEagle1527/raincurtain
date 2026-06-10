import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/plugin_manager.dart';
import 'raincurtain_core_handler.dart';
import 'raincurtain_storage_handler.dart';
import 'raincurtain_personal_storage_handler.dart';

/// RainCurtain 核心 API 的 JS 生成和 Handler 注册的入口 Mixin
mixin RainCurtainApiMixin {
  /// 生成 RainCurtain API 注入 JS
  String generateRainCurtainAPI(String pluginId) {
    return '''
(function() {
  function _call(handler, args) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(handler, args);
  }

  window.RainCurtain = {
    // ========== 元数据 ==========
    pluginId: '$pluginId',
    
    ${RainCurtainCoreHandler.generateJS()}
    
    ${RainCurtainStorageHandler.generateJS()}
    
    ${RainCurtainPersonalStorageHandler.generateJS()}
  };
  
  // 标记 API 已就绪
  window.__raincurtain_ready__ = true;
  window.dispatchEvent(new Event('raincurtain:ready'));
})();
''';
  }

  /// 注册核心 API Handlers
  void registerApiHandlers(
    InAppWebViewController controller, {
    required BuildContext context,
    required LocalPlugin plugin,
    String? poolId,
    String? poolPluginId,
  }) {
    // 1. 注册核心输入输出 Handler
    RainCurtainCoreHandler.register(
      controller,
      context: context,
      plugin: plugin,
      poolId: poolId,
      poolPluginId: poolPluginId,
    );

    // 2. 注册结构化数据库存储 Handler
    RainCurtainStorageHandler.register(
      controller,
      context: context,
      plugin: plugin,
      poolId: poolId,
      poolPluginId: poolPluginId,
    );

    // 3. 注册专属物理目录存储 Handler
    RainCurtainPersonalStorageHandler.register(
      controller,
      plugin: plugin,
    );
  }
}
