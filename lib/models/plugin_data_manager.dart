import 'package:flutter/foundation.dart';

import 'database_manager.dart';
import 'plugin_storage_manager.dart';

/// 插件数据统计信息
class PluginDataStats {
  final int storageSize;
  final int storageItemCount;

  PluginDataStats({
    required this.storageSize,
    required this.storageItemCount,
  });

  int get totalSize => storageSize;
  int get totalItems => storageItemCount;
}

/// 插件数据管理器
/// 管理插件的结构化存储数据
class PluginDataManager extends ChangeNotifier {
  late PluginStorageManager pluginStorageManager;

  /// 数据库文件所在目录路径（用于 UI 显示）
  String get dataDir => DatabaseManager.instance.dbDirectoryPath;

  bool _isInit = false;
  bool get isInit => _isInit;

  PluginDataManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final db = DatabaseManager.database;
      pluginStorageManager = PluginStorageManager(database: db);

      _isInit = true;
      notifyListeners();

      debugPrint('PluginDataManager initialized (SQLite)');
    } catch (e, stackTrace) {
      debugPrint('PluginDataManager init failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isInit = false;
    }
  }

  /// 获取插件的总数据大小
  Future<int> getTotalSizeForPlugin(String pluginId) async {
    return pluginStorageManager.getStorageSize(pluginId);
  }

  /// 获取插件的数据统计
  Future<PluginDataStats> getStatsForPlugin(String pluginId) async {
    final storageSize =
        await pluginStorageManager.getStorageSize(pluginId);
    final storageItemCount =
        await pluginStorageManager.getStorageItemCount(pluginId);

    return PluginDataStats(
      storageSize: storageSize,
      storageItemCount: storageItemCount,
    );
  }

  /// 获取所有插件的数据统计
  Future<Map<String, PluginDataStats>> getAllPluginsDataStats() async {
    final stats = <String, PluginDataStats>{};
    final storagePluginIds = await pluginStorageManager.getAllPluginIds();

    for (final pluginId in storagePluginIds) {
      stats[pluginId] = await getStatsForPlugin(pluginId);
    }

    return stats;
  }

  /// 清除插件的所有存储数据
  Future<void> clearAllDataForPlugin(String pluginId) async {
    await clearStorageForPlugin(pluginId);
  }

  /// 清除插件的存储数据（删除所有表）
  Future<void> clearStorageForPlugin(String pluginId) async {
    await pluginStorageManager.dropTablesForPlugin(pluginId);
    notifyListeners();
    debugPrint('Storage cleared for plugin: $pluginId');
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
    final storagePluginIds = await pluginStorageManager.getAllPluginIds();
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
