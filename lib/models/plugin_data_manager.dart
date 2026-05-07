import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'localstorage_manager.dart';

/// 插件数据统计信息
class PluginDataStats {
  final int localStorageSize;
  final int localStorageItemCount;

  PluginDataStats({
    required this.localStorageSize,
    required this.localStorageItemCount,
  });

  int get totalSize => localStorageSize;
  int get totalItems => localStorageItemCount;
}

/// 插件数据管理器
/// 管理 LocalStorage 数据（Cookie 存储已移除）
class PluginDataManager extends ChangeNotifier {
  late Directory dataDir;
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

      final localStorageDir = Directory(p.join(dataDir.path, 'localstorage'));
      await localStorageDir.create(recursive: true);

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
    return localStorageManager.getLocalStorageSize(pluginId);
  }

  /// 获取插件的数据统计
  Future<PluginDataStats> getStatsForPlugin(String pluginId) async {
    final localStorageSize =
        await localStorageManager.getLocalStorageSize(pluginId);
    final localStorageItemCount =
        await localStorageManager.getLocalStorageItemCount(pluginId);

    return PluginDataStats(
      localStorageSize: localStorageSize,
      localStorageItemCount: localStorageItemCount,
    );
  }

  /// 获取所有插件的数据统计
  Future<Map<String, PluginDataStats>> getAllPluginsDataStats() async {
    final stats = <String, PluginDataStats>{};
    final storagePluginIds = await localStorageManager.getAllPluginIds();

    for (final pluginId in storagePluginIds) {
      stats[pluginId] = await getStatsForPlugin(pluginId);
    }

    return stats;
  }

  /// 清除插件的所有数据
  Future<void> clearAllDataForPlugin(String pluginId) async {
    await clearLocalStorageForPlugin(pluginId);
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
    final storagePluginIds = await localStorageManager.getAllPluginIds();
    return {...storagePluginIds};
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
