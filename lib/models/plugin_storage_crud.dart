import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'plugin_manifest.dart';
import 'plugin_storage_lifecycle.dart'; // 需要用到 dbTableName

class PluginStorageCRUD {
  final Database _db;
  final Map<String, List<StorageTableDefinition>> _schemaCache;

  PluginStorageCRUD(this._db, this._schemaCache);

  // ─── Schema 验证 ──────────────────────────────────────────

  bool _isValidTable(String pluginId, String tableName) {
    final tables = _schemaCache[pluginId];
    if (tables == null) return false;
    return tables.any((t) => t.name == tableName);
  }

  StorageTableDefinition? _getTableDef(String pluginId, String tableName) {
    final tables = _schemaCache[pluginId];
    if (tables == null) return null;
    for (final t in tables) {
      if (t.name == tableName) return t;
    }
    return null;
  }

  bool _isValidColumn(StorageTableDefinition tableDef, String columnName) {
    if (columnName == '_id') return true;
    return tableDef.columns.any((c) => c.name == columnName);
  }

  StorageColumnDefinition? _getColumnDef(
      StorageTableDefinition tableDef, String columnName) {
    for (final c in tableDef.columns) {
      if (c.name == columnName) return c;
    }
    return null;
  }

  // ─── CRUD 操作 ──────────────────────────────────────────

  Future<int> insert(
      String pluginId, String tableName, List<Map<String, dynamic>> rows) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);
    int insertedCount = 0;

    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        final sanitized = _sanitizeRow(tableDef, row);
        batch.insert(fullName, sanitized);
      }
      final results = await batch.commit();
      insertedCount = results.length;
    });

    return insertedCount;
  }

  Future<List<Map<String, dynamic>>> query(
    String pluginId,
    String tableName, {
    Map<String, dynamic>? where,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);
    final tableDef = _getTableDef(pluginId, tableName);

    if (tableDef != null) {
      String? whereClause;
      List<Object?>? whereArgs;

      if (where != null && where.isNotEmpty) {
        final result = _buildWhereClause(tableDef, where);
        whereClause = result.$1;
        whereArgs = result.$2;
      }

      String? safeOrderBy;
      if (orderBy != null && orderBy.isNotEmpty) {
        safeOrderBy = _sanitizeOrderBy(tableDef, orderBy);
      }

      final rows = await _db.query(
        fullName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: safeOrderBy,
        limit: limit,
        offset: offset,
      );

      return rows.map((row) => _convertRowFromDb(tableDef, row)).toList();
    }

    final tableExists = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [fullName],
    );
    if (tableExists.isEmpty) return [];

    final safeNameRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

    String sql = 'SELECT * FROM $fullName';
    List<Object?>? args;

    if (where != null && where.isNotEmpty) {
      final clauses = <String>[];
      args = <Object?>[];
      for (final entry in where.entries) {
        if (!safeNameRegex.hasMatch(entry.key)) {
          debugPrint('Invalid key in loose-mode where: ${entry.key}, skipping');
          continue;
        }
        clauses.add('${entry.key} = ?');
        args.add(entry.value);
      }
      if (clauses.isNotEmpty) {
        sql += ' WHERE ${clauses.join(' AND ')}';
      }
    }

    if (orderBy != null && orderBy.isNotEmpty) {
      final orderParts = orderBy.split(',');
      final sanitizedOrder = <String>[];
      for (final part in orderParts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final tokens = trimmed.split(RegExp(r'\s+'));
        final colName = tokens[0];
        final direction =
            tokens.length > 1 ? tokens[1].toUpperCase() : 'ASC';
        if (!safeNameRegex.hasMatch(colName)) {
          debugPrint('Invalid column in loose-mode orderBy: $colName, skipping');
          continue;
        }
        if (direction != 'ASC' && direction != 'DESC') {
          sanitizedOrder.add('$colName ASC');
        } else {
          sanitizedOrder.add('$colName $direction');
        }
      }
      if (sanitizedOrder.isNotEmpty) {
        sql += ' ORDER BY ${sanitizedOrder.join(', ')}';
      }
    }
    if (limit != null) {
      sql += ' LIMIT $limit';
      if (offset != null) {
        sql += ' OFFSET $offset';
      }
    }

    return await _db.rawQuery(sql, args);
  }

  Future<int> update(
    String pluginId,
    String tableName,
    Map<String, dynamic> values,
    Map<String, dynamic>? where,
  ) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);

    final sanitizedValues = _sanitizeRow(tableDef, values);

    String? whereClause;
    List<Object?>? whereArgs;

    if (where != null && where.isNotEmpty) {
      final result = _buildWhereClause(tableDef, where);
      whereClause = result.$1;
      whereArgs = result.$2;
    }

    return await _db.update(
      fullName,
      sanitizedValues,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<int> delete(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);

    String? whereClause;
    List<Object?>? whereArgs;

    if (where != null && where.isNotEmpty) {
      final result = _buildWhereClause(tableDef, where);
      whereClause = result.$1;
      whereArgs = result.$2;
    }

    return await _db.delete(
      fullName,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<int> count(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);

    String query = 'SELECT COUNT(*) as count FROM $fullName';
    List<Object?>? args;

    if (where != null && where.isNotEmpty) {
      final result = _buildWhereClause(tableDef, where);
      query += ' WHERE ${result.$1}';
      args = result.$2;
    }

    final result = await _db.rawQuery(query, args);
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> clear(String pluginId, String tableName) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final fullName = PluginStorageLifecycle.dbTableName(pluginId, tableName);
    await _db.delete(fullName);
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

  Map<String, dynamic> _sanitizeRow(
      StorageTableDefinition tableDef, Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      if (entry.key == '_id') continue;

      final colDef = _getColumnDef(tableDef, entry.key);
      if (colDef == null) continue;

      result[entry.key] = _convertValueToDb(colDef, entry.value);
    }
    return result;
  }

  dynamic _convertValueToDb(StorageColumnDefinition colDef, dynamic value) {
    if (value == null) return null;
    if (colDef.type == 'boolean') {
      if (value is bool) return value ? 1 : 0;
      if (value is int) return value;
      if (value is String) return value.toLowerCase() == 'true' ? 1 : 0;
      return 0;
    }
    return value;
  }

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

  (String, List<Object?>) _buildWhereClause(
      StorageTableDefinition tableDef, Map<String, dynamic> where) {
    final clauses = <String>[];
    final args = <Object?>[];

    for (final entry in where.entries) {
      if (!_isValidColumn(tableDef, entry.key)) {
        throw ArgumentError('Invalid column "${entry.key}" in where clause');
      }

      if (entry.key == '_id') {
        clauses.add('_id = ?');
        args.add(entry.value);
      } else {
        final colDef = _getColumnDef(tableDef, entry.key);
        clauses.add('${entry.key} = ?');
        if (colDef != null) {
          args.add(_convertValueToDb(colDef, entry.value));
        } else {
          args.add(entry.value);
        }
      }
    }

    return (clauses.join(' AND '), args);
  }

  String? _sanitizeOrderBy(StorageTableDefinition tableDef, String orderBy) {
    final parts = orderBy.split(',');
    final sanitized = <String>[];

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final tokens = trimmed.split(RegExp(r'\s+'));
      final colName = tokens[0];
      final direction =
          tokens.length > 1 ? tokens[1].toUpperCase() : 'ASC';

      if (!_isValidColumn(tableDef, colName)) {
        debugPrint('Invalid column in orderBy: $colName, skipping');
        continue;
      }
      if (direction != 'ASC' && direction != 'DESC') {
        debugPrint('Invalid direction in orderBy: $direction, using ASC');
        sanitized.add('$colName ASC');
      } else {
        sanitized.add('$colName $direction');
      }
    }

    return sanitized.isEmpty ? null : sanitized.join(', ');
  }
}
