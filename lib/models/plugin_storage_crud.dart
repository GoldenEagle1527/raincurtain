import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'plugin_manifest.dart';
import 'plugin_storage_lifecycle.dart'; // 需要用到 dbTableName

class PluginStorageCRUD {
  final Database _db;
  final Map<String, List<StorageTableDefinition>> _schemaCache;

  PluginStorageCRUD(this._db, this._schemaCache);

  // ─── Schema 验证 ──────────────────────────────────────────



  StorageColumnDefinition? _getColumnDef(
      StorageTableDefinition tableDef, String columnName) {
    for (final c in tableDef.columns) {
      if (c.name == columnName) return c;
    }
    return null;
  }



  // ─── 原生 SQL 执行 ──────────────────────────────────────

  /// 执行原生 SQL 语句（完全解禁，支持所有 SQL 语法）
  /// 自动将逻辑表名改写为插件隔离的物理表名
  Future<dynamic> executeSql(
    String pluginId,
    String sql,
    List<Object?> params,
  ) async {
    // 表名改写：将插件可见的逻辑表名替换为带前缀的物理隔离表名
    final rewrittenSql = _rewriteTableNames(pluginId, sql);

    // 判断语句类型
    final trimmed = rewrittenSql.trimLeft().toUpperCase();
    if (trimmed.startsWith('SELECT') || trimmed.startsWith('WITH') || trimmed.startsWith('PRAGMA') || trimmed.startsWith('EXPLAIN')) {
      // 只读查询
      final rows = await _db.rawQuery(rewrittenSql, params);
      // 尝试对结果做 boolean 转换
      final tableDef = _findTableDefForQuery(pluginId, sql);
      if (tableDef != null) {
        return rows.map((row) => _convertRowFromDb(tableDef, row)).toList();
      }
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } else {
      // DML: INSERT/UPDATE/DELETE/REPLACE 及其他
      final changes = await _db.rawUpdate(rewrittenSql, params);
      return {'changes': changes};
    }
  }

  /// 将 SQL 中的逻辑表名替换为物理隔离表名
  String _rewriteTableNames(String pluginId, String sql) {
    final tables = _schemaCache[pluginId];
    if (tables == null || tables.isEmpty) return sql;

    // 按表名长度降序排列，防止短名匹配到长名的子串
    final sortedTables = List<StorageTableDefinition>.from(tables)
      ..sort((a, b) => b.name.length.compareTo(a.name.length));

    String result = sql;
    for (final table in sortedTables) {
      final fullName = PluginStorageLifecycle.dbTableName(pluginId, table.name);
      // 使用 word boundary 正则替换，避免部分匹配
      result = result.replaceAll(
        RegExp('\\b${RegExp.escape(table.name)}\\b'),
        fullName,
      );
    }
    return result;
  }

  /// 尝试从 SQL 中推断查询的目标表定义（用于 boolean 转换）
  StorageTableDefinition? _findTableDefForQuery(String pluginId, String sql) {
    final tables = _schemaCache[pluginId];
    if (tables == null) return null;

    final upperSql = sql.toUpperCase();
    // 简单匹配：FROM 后面的第一个表名
    for (final table in tables) {
      if (upperSql.contains(RegExp('\\bFROM\\s+${RegExp.escape(table.name.toUpperCase())}\\b'))) {
        return table;
      }
    }
    return null;
  }

  // ─── 统计方法 ──────────────────────────────────────────

  Future<int> getStorageSize(String pluginId) async {
    final tableNames = await getTableNames(pluginId);
    int totalSize = 0;

    for (final name in tableNames) {
      try {
        final columnsInfo = await _db.rawQuery('PRAGMA table_info($name)');
        final textColumns = <String>[];
        for (final col in columnsInfo) {
          final colName = col['name'] as String;
          if (colName == '_id') continue;
          textColumns.add(colName);
        }

        if (textColumns.isEmpty) continue;

        final sums = textColumns
            .map((c) => 'COALESCE(SUM(LENGTH($c)), 0)')
            .join(' + ');
        final result =
            await _db.rawQuery('SELECT ($sums) as total_size FROM $name');
        if (result.isNotEmpty && result.first['total_size'] != null) {
          totalSize += (result.first['total_size'] as int?) ?? 0;
        }
      } catch (e) {
        debugPrint('Failed to get size for table $name: $e');
      }
    }

    return totalSize;
  }

  Future<int> getStorageItemCount(String pluginId) async {
    final tableNames = await getTableNames(pluginId);
    int totalCount = 0;

    for (final name in tableNames) {
      try {
        final result =
            await _db.rawQuery('SELECT COUNT(*) as count FROM $name');
        totalCount += (result.first['count'] as int?) ?? 0;
      } catch (e) {
        debugPrint('Failed to get count for table $name: $e');
      }
    }

    return totalCount;
  }

  Future<List<String>> getTableNames(String pluginId) async {
    final prefix = _dbTablePrefix(pluginId);
    final tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
      ['$prefix%'],
    );
    return tables.map((r) => r['name'] as String).toList();
  }

  Future<List<String>> getShortTableNames(String pluginId) async {
    final prefix = _dbTablePrefix(pluginId);
    final fullNames = await getTableNames(pluginId);
    return fullNames.map((n) => n.substring(prefix.length)).toList();
  }

  Future<List<String>> getAllPluginIds() async {
    try {
      final tables = await _db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'plugin_%'",
      );

      final pluginIds = <String>{};
      for (final row in tables) {
        final name = row['name'] as String;
        final doubleUnderscoreIdx = name.indexOf('__');
        if (doubleUnderscoreIdx > 7) {
          final sanitizedId = name.substring(7, doubleUnderscoreIdx);
          final id = _restoreUuid(sanitizedId);
          if (id != null) {
            pluginIds.add(id);
          }
        }
      }

      return pluginIds.toList();
    } catch (e) {
      debugPrint('Failed to get all plugin IDs: $e');
      return [];
    }
  }

  static String? _restoreUuid(String sanitized) {
    final parts = sanitized.split('_');
    if (parts.length != 5) return null;
    if (parts[0].length != 8 ||
        parts[1].length != 4 ||
        parts[2].length != 4 ||
        parts[3].length != 4 ||
        parts[4].length != 12) {
      return null;
    }
    return parts.join('-');
  }

  static String _dbTablePrefix(String pluginId) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}__';
  }

  // ─── 内部辅助 ──────────────────────────────────────────



  Map<String, dynamic> _convertRowFromDb(
      StorageTableDefinition tableDef, Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      if (entry.key == '_id') {
        result['_id'] = entry.value;
        continue;
      }

      final colDef = _getColumnDef(tableDef, entry.key);
      if (colDef != null && colDef.type == 'boolean') {
        result[entry.key] =
            entry.value != null && entry.value != 0;
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }


}
