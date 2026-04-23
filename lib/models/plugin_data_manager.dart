import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cookie_storage_manager.dart';
import 'localstorage_manager.dart';

/// 插件数据统计信息
class PluginDataStats {
  final int cookieSize;
  final int localStorageSize;
  final int cookieCount;
  final int localStorageItemCount;

  PluginDataStats({
    required this.cookieSize,
    required this.localStorageSize,
    required this.cookieCount,
    required this.localStorageItemCount,
  });

  int get totalSize => cookieSize + localStorageSize;
  int get totalItems => cookieCount + localStorageItemCount;
}

/// 插件数据管理器
/// 统一管理 Cookie 和 LocalStorage 数据
class PluginDataManager extends ChangeNotifier {
  late Directory dataDir;
  late CookieStorageManager cookieManager;
  late LocalStorageManager localStorageManager;

  bool _isInit = false;
  bool get isInit => _isInit;

  PluginDataManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      dataDir = Directory(p.join(supportDir.path, 'RainCurtainPluginsData'));

      final cookieDir = Directory(p.join(dataDir.path, 'cookies'));
      final localStorageDir = Directory(p.join(dataDir.path, 'localstorage'));

      await cookieDir.create(recursive: true);
      await localStorageDir.create(recursive: true);

      cookieManager = CookieStorageManager(storageDir: cookieDir);
      localStorageManager = LocalStorageManager(storageDir: localStorageDir);

      _isInit = true;
      notifyListeners();
      
      debugPrint('PluginDataManager initialized at: ${dataDir.path}');
    } catch (e, stackTrace) {
      debugPrint('PluginDataManager init failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isInit = false;
    }
  }

  /// 获取插件的总数据大小
  Future<int> getTotalSizeForPlugin(String pluginId) async {
    final cookieSize = await cookieManager.getCookiesSizeForPlugin(pluginId);
    final storageSize = await localStorageManager.getLocalStorageSize(pluginId);
    return cookieSize + storageSize;
  }

  /// 获取插件的数据统计
  Future<PluginDataStats> getStatsForPlugin(String pluginId) async {
    final cookieSize = await cookieManager.getCookiesSizeForPlugin(pluginId);
    final localStorageSize = await localStorageManager.getLocalStorageSize(pluginId);
    final cookieCount = await cookieManager.getCookieCountForPlugin(pluginId);
    final localStorageItemCount = await localStorageManager.getLocalStorageItemCount(pluginId);

    return PluginDataStats(
      cookieSize: cookieSize,
      localStorageSize: localStorageSize,
      cookieCount: cookieCount,
      localStorageItemCount: localStorageItemCount,
    );
  }

  /// 获取所有插件的数据统计
  Future<Map<String, PluginDataStats>> getAllPluginsDataStats() async {
    final stats = <String, PluginDataStats>{};

    // 获取所有有 Cookie 数据的插件
    final cookiePluginIds = await cookieManager.getAllPluginIds();
    
    // 获取所有有 LocalStorage 数据的插件
    final storagePluginIds = await localStorageManager.getAllPluginIds();

    // 合并插件 ID 列表
    final allPluginIds = <String>{...cookiePluginIds, ...storagePluginIds};

    for (final pluginId in allPluginIds) {
      stats[pluginId] = await getStatsForPlugin(pluginId);
    }

    return stats;
  }

  /// 清除插件的所有数据
  Future<void> clearAllDataForPlugin(String pluginId) async {
    await clearCookieForPlugin(pluginId);
    await clearLocalStorageForPlugin(pluginId);
  }

  /// 清除插件的 Cookie 数据
  Future<void> clearCookieForPlugin(String pluginId) async {
    await cookieManager.clearCookiesForPlugin(pluginId);
    notifyListeners();
    debugPrint('Cookies cleared for plugin: $pluginId');
  }

  /// 清除插件的 LocalStorage 数据
  Future<void> clearLocalStorageForPlugin(String pluginId) async {
    await localStorageManager.clearLocalStorage(pluginId);
    notifyListeners();
    debugPrint('LocalStorage cleared for plugin: $pluginId');
  }

  /// 清除所有插件的数据
  Future<void> clearAllData() async {
    final allPluginIds = await getAllPluginIds();
    for (final pluginId in allPluginIds) {
      await clearAllDataForPlugin(pluginId);
    }
    notifyListeners();
    debugPrint('All plugin data cleared');
  }

  /// 获取所有插件 ID
  Future<Set<String>> getAllPluginIds() async {
    final cookiePluginIds = await cookieManager.getAllPluginIds();
    final storagePluginIds = await localStorageManager.getAllPluginIds();
    return {...cookiePluginIds, ...storagePluginIds};
  }

  /// 获取总数据大小
  Future<int> getTotalDataSize() async {
    int totalSize = 0;
    final allPluginIds = await getAllPluginIds();
    
    for (final pluginId in allPluginIds) {
      totalSize += await getTotalSizeForPlugin(pluginId);
    }
    
    return totalSize;
  }

  /// 格式化字节大小为可读字符串
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
