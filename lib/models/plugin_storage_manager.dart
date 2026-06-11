import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'plugin_manifest.dart';
import 'plugin_storage_lifecycle.dart';
import 'plugin_storage_crud.dart';
import 'plugin_storage_outputs.dart';

/// 插件存储管理器
/// 负责管理每个插件的独立结构化表（Facade 模式代理）
/// 全局单例，由 DatabaseManager.init() 初始化
class PluginStorageManager {
  static PluginStorageManager? _instance;

  /// 获取已初始化的单例实例
  static PluginStorageManager get instance {
    if (_instance == null) {
      throw StateError('PluginStorageManager has not been initialized. '
          'Ensure DatabaseManager.init() has been called first.');
    }
    return _instance!;
  }

  /// 初始化单例（由 DatabaseManager.init() 调用）
  static void init(Database db) {
    _instance ??= PluginStorageManager._internal(db);
  }

  final Database _db;
  final Map<String, List<StorageTableDefinition>> _schemaCache = {};

  late final PluginStorageLifecycle lifecycle;
  late final PluginStorageCRUD crud;
  late final PluginStorageOutputs outputs;

  PluginStorageManager._internal(this._db) {
    lifecycle = PluginStorageLifecycle(_db, _schemaCache);
    crud = PluginStorageCRUD(_db, _schemaCache);
    outputs = PluginStorageOutputs(_db);
  }

  // ─── 表名辅助 ──────────────────────────────────────────────

  /// 生成数据库表名：plugin_{sanitized_uuid}__{table_name}
  static String dbTableName(String pluginId, String tableName) {
    return PluginStorageLifecycle.dbTableName(pluginId, tableName);
  }

  // ─── 表管理 ──────────────────────────────────────────

  /// 确保插件的所有存储表存在（幂等，可在每次插件加载时调用）
  /// 返回一个 bool，指示是否发生了任何表结构变更
  Future<bool> ensureTablesForPlugin(
      String pluginId, List<StorageTableDefinition> tables) {
    return lifecycle.ensureTablesForPlugin(pluginId, tables);
  }

  /// 删除插件的所有存储表（卸载时使用）
  Future<void> dropTablesForPlugin(String pluginId) {
    return lifecycle.dropTablesForPlugin(pluginId);
  }

  /// 注册插件的 schema（不创建表，仅缓存，用于 handler 验证）
  void registerSchema(String pluginId, List<StorageTableDefinition> tables) {
    _schemaCache[pluginId] = tables;
  }



  // ─── 原生 SQL 执行 ──────────────────────────────────────

  /// 执行原生 SQL 语句
  Future<dynamic> executeSql(
    String pluginId,
    String sql,
    List<Object?> params,
  ) {
    return crud.executeSql(pluginId, sql, params);
  }

  // ─── 统计方法 ──────────────────────────────────────────

  /// 获取插件所有表的数据大小（字节，近似值）
  Future<int> getStorageSize(String pluginId) {
    return crud.getStorageSize(pluginId);
  }

  /// 获取插件所有表的总行数
  Future<int> getStorageItemCount(String pluginId) {
    return crud.getStorageItemCount(pluginId);
  }

  /// 获取插件的所有数据库表名（全名）
  Future<List<String>> getTableNames(String pluginId) {
    return crud.getTableNames(pluginId);
  }

  /// 获取插件的所有表名（短名，不含前缀）
  Future<List<String>> getShortTableNames(String pluginId) {
    return crud.getShortTableNames(pluginId);
  }

  /// 获取所有有存储表的插件 ID
  Future<List<String>> getAllPluginIds() {
    return crud.getAllPluginIds();
  }

  // ─── 隐式输出表 ──────────────────────────────────────────

  /// 写入或更新一个输出值（upsert）
  Future<void> upsertOutput(String pluginId, String name, dynamic value) {
    return outputs.upsertOutput(pluginId, name, value);
  }

  /// 获取插件的所有输出值
  Future<Map<String, dynamic>> getOutputs(String pluginId) {
    return outputs.getOutputs(pluginId);
  }
}
