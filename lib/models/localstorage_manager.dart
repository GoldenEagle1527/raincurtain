import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// LocalStorage 管理器
/// 负责管理插件的 LocalStorage 数据持久化
class LocalStorageManager {
  final Directory storageDir;

  LocalStorageManager({required this.storageDir});

  /// 获取插件的 LocalStorage 文件路径
  String _getStorageFilePath(String pluginId) {
    return p.join(storageDir.path, '${pluginId}_localstorage.json');
  }

  /// 保存 LocalStorage 数据
  Future<void> saveLocalStorage(
    String pluginId,
    Map<String, dynamic> data,
  ) async {
    try {
      final file = File(_getStorageFilePath(pluginId));
      
      // 如果数据为空，则不需要保存文件，且可以删除已有文件
      if (data.isEmpty) {
        if (await file.exists()) {
          await file.delete();
          debugPrint('LocalStorage cleared (empty data) for plugin: $pluginId');
        }
        return;
      }

      final jsonData = {
        'data': data,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(
        jsonEncode(jsonData),
        flush: true,
      );
      debugPrint('LocalStorage saved for plugin: $pluginId');
    } catch (e) {
      debugPrint('Failed to save LocalStorage for $pluginId: $e');
    }
  }

  /// 更新单个键值对
  Future<void> setItem(String pluginId, String key, String value) async {
    try {
      final currentData = await loadLocalStorage(pluginId);
      currentData[key] = value;
      await saveLocalStorage(pluginId, currentData);
    } catch (e) {
      debugPrint('Failed to set item for $pluginId: $e');
    }
  }

  /// 删除单个键
  Future<void> removeItem(String pluginId, String key) async {
    try {
      final currentData = await loadLocalStorage(pluginId);
      currentData.remove(key);
      await saveLocalStorage(pluginId, currentData);
    } catch (e) {
      debugPrint('Failed to remove item for $pluginId: $e');
    }
  }

  /// 加载 LocalStorage 数据
  Future<Map<String, dynamic>> loadLocalStorage(String pluginId) async {
    try {
      final file = File(_getStorageFilePath(pluginId));
      if (!await file.exists()) {
        return {};
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(jsonData['data'] as Map? ?? {});
      
      // 如果由于历史原因读取到空数据，主动清理文件
      if (data.isEmpty) {
        await file.delete();
      }
      
      return data;
    } catch (e) {
      debugPrint('Failed to load LocalStorage for $pluginId: $e');
      final file = File(_getStorageFilePath(pluginId));
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return {};
    }
  }

  /// 清除 LocalStorage 数据
  Future<void> clearLocalStorage(String pluginId) async {
    try {
      final file = File(_getStorageFilePath(pluginId));
      if (await file.exists()) {
        await file.delete();
        debugPrint('LocalStorage cleared for plugin: $pluginId');
      }
    } catch (e) {
      debugPrint('Failed to clear LocalStorage for $pluginId: $e');
    }
  }

  /// 计算 LocalStorage 数据大小（字节）
  Future<int> getLocalStorageSize(String pluginId) async {
    try {
      final file = File(_getStorageFilePath(pluginId));
      if (await file.exists()) {
        // 尝试先判断是否为空数据，避免遗留空文件影响真实大小统计
        final content = await file.readAsString();
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        final data = jsonData['data'] as Map?;
        if (data == null || data.isEmpty) {
          await file.delete();
          return 0;
        }
        return await file.length();
      }
      return 0;
    } catch (e) {
      debugPrint('Failed to get LocalStorage size for $pluginId: $e');
      return 0;
    }
  }

  /// 获取 LocalStorage 项数量
  Future<int> getLocalStorageItemCount(String pluginId) async {
    try {
      final data = await loadLocalStorage(pluginId);
      return data.length;
    } catch (e) {
      debugPrint('Failed to get LocalStorage item count for $pluginId: $e');
      return 0;
    }
  }

  /// 获取所有键
  Future<List<String>> getKeys(String pluginId) async {
    try {
      final currentData = await loadLocalStorage(pluginId);
      return currentData.keys.toList();
    } catch (e) {
      debugPrint('Failed to get keys for $pluginId: $e');
      return [];
    }
  }

  /// 获取单个项
  Future<dynamic> getItem(String pluginId, String key) async {
    try {
      final currentData = await loadLocalStorage(pluginId);
      final value = currentData[key];
      if (value is String) {
        try {
          return jsonDecode(value);
        } catch (_) {
          return value;
        }
      }
      return value;
    } catch (e) {
      debugPrint('Failed to get item for $pluginId: $e');
      return null;
    }
  }

  /// 获取所有插件的 LocalStorage 文件列表
  Future<List<String>> getAllPluginIds() async {
    try {
      if (!await storageDir.exists()) {
        return [];
      }

      final files = await storageDir.list().toList();
      final pluginIds = <String>[];

      for (final file in files) {
        if (file is File && file.path.endsWith('_localstorage.json')) {
          final filename = p.basename(file.path);
          final pluginId = filename.replaceAll('_localstorage.json', '');
          
          // 在获取列表时检查并清理空数据文件
          try {
            final content = await file.readAsString();
            final jsonData = jsonDecode(content) as Map<String, dynamic>;
            final data = jsonData['data'] as Map?;
            if (data == null || data.isEmpty) {
              await file.delete();
              continue;
            }
          } catch (_) {
            await file.delete();
            continue;
          }

          pluginIds.add(pluginId);
        }
      }

      return pluginIds;
    } catch (e) {
      debugPrint('Failed to get all plugin IDs: $e');
      return [];
    }
  }
}
