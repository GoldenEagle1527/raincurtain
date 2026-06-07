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
  Future<void> ensureTablesForPlugin(
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

  // ─── CRUD 操作 ──────────────────────────────────────────

  /// 插入一行或多行数据
  Future<int> insert(
      String pluginId, String tableName, List<Map<String, dynamic>> rows) {
    return crud.insert(pluginId, tableName, rows);
  }

  /// 查询数据
  Future<List<Map<String, dynamic>>> query(
    String pluginId,
    String tableName, {
    Map<String, dynamic>? where,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return crud.query(
      pluginId,
      tableName,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// 更新数据
  Future<int> update(
    String pluginId,
    String tableName,
    Map<String, dynamic> values,
    Map<String, dynamic>? where,
  ) {
    return crud.update(pluginId, tableName, values, where);
  }

  /// 删除数据
  Future<int> delete(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) {
    return crud.delete(pluginId, tableName, where);
  }

  /// 计数
  Future<int> count(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) {
    return crud.count(pluginId, tableName, where);
  }

  /// 清空表
  Future<void> clear(String pluginId, String tableName) {
    return crud.clear(pluginId, tableName);
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
