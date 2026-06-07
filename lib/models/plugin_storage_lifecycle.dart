import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'plugin_manifest.dart';

class PluginStorageLifecycle {
  final Database _db;
  final Map<String, List<StorageTableDefinition>> _schemaCache;

  PluginStorageLifecycle(this._db, this._schemaCache);

  /// 确保插件的所有存储表存在（幂等，可在每次插件加载时调用）
  Future<void> ensureTablesForPlugin(
      String pluginId, List<StorageTableDefinition> tables) async {
    _schemaCache[pluginId] = tables;

    for (final table in tables) {
      final fullName = dbTableName(pluginId, table.name);

      // 检查表是否已存在
      final existing = await _db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [fullName],
      );

      if (existing.isNotEmpty) {
        // 表已存在，获取现有列信息（名称 → SQLite 类型）
        final columnsInfo = await _db.rawQuery('PRAGMA table_info($fullName)');
        final existingColumns = <String, String>{}; // name → type (大写)
        for (final col in columnsInfo) {
          final colName = col['name'] as String;
          if (colName != '_id') {
            existingColumns[colName] =
                (col['type'] as String).toUpperCase();
          }
        }

        final expectedColumns = {
          for (final c in table.columns) c.name: c.sqliteType,
        };

        // 如果完全一致，跳过
        if (_columnsMatch(existingColumns, expectedColumns)) {
          continue;
        }

        // 检查是否存在不可兼容的类型变更
        bool hasTypeConflict = false;
        for (final entry in expectedColumns.entries) {
          final existingType = existingColumns[entry.key];
          if (existingType != null && existingType != entry.value) {
            debugPrint(
                'Type conflict for $fullName.${entry.key}: '
                'existing=$existingType, expected=${entry.value}');
            hasTypeConflict = true;
            break;
          }
        }

        if (hasTypeConflict) {
          // 存在类型冲突，必须 DROP 重建
          debugPrint(
              'Incompatible schema change for $fullName, '
              'dropping and recreating (type conflict)');
          await _db.execute('DROP TABLE IF EXISTS $fullName');
        } else {
          // 无类型冲突，尝试增量迁移：ADD COLUMN 补齐新列
          final columnsToAdd = expectedColumns.keys
              .where((name) => !existingColumns.containsKey(name))
              .toList();

          for (final colName in columnsToAdd) {
            final colType = expectedColumns[colName]!;
            await _db.execute(
                'ALTER TABLE $fullName ADD COLUMN $colName $colType');
            debugPrint('Added column $colName ($colType) to $fullName');
          }

          // 旧表中多出的列（已删除的列）不做处理，保留在表中
          final droppedColumns = existingColumns.keys
              .where((name) => !expectedColumns.containsKey(name))
              .toSet();
          if (droppedColumns.isNotEmpty) {
            debugPrint(
                'Columns no longer in schema for $fullName: '
                '$droppedColumns (kept in table, ignored by CRUD)');
          }

          continue; // 增量迁移完成，不需要重建
        }
      }

      // 创建表（首次或 DROP 后重建）
      final columnDefs = table.columns
          .map((c) => '${c.name} ${c.sqliteType}')
          .join(', ');
      await _db.execute('''
        CREATE TABLE IF NOT EXISTS $fullName (
          _id INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnDefs
        )
      ''');
      debugPrint('Created storage table: $fullName');
    }
  }

  /// 检查现有表结构是否已满足期望 schema
  bool _columnsMatch(
      Map<String, String> existing, Map<String, String> expected) {
    for (final entry in expected.entries) {
      final existingType = existing[entry.key];
      if (existingType == null || existingType != entry.value) {
        return false;
      }
    }
    return true;
  }

  /// 删除插件的所有存储表（卸载时使用）
  Future<void> dropTablesForPlugin(String pluginId) async {
    final prefix = _dbTablePrefix(pluginId);

    // 查找所有匹配的表
    final tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
      ['$prefix%'],
    );

    for (final row in tables) {
      final tableName = row['name'] as String;
      await _db.execute('DROP TABLE IF EXISTS $tableName');
      debugPrint('Dropped storage table: $tableName');
    }

    _schemaCache.remove(pluginId);
  }

  /// 静态辅助方法：生成数据库表名
  static String dbTableName(String pluginId, String tableName) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}__$tableName';
  }

  /// 从数据库表名解析出 pluginId 前缀
  static String _dbTablePrefix(String pluginId) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}__';
  }
}
