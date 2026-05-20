import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'plugin_manifest.dart';

/// 插件存储管理器
/// 负责管理每个插件的独立结构化表（替代旧的 LocalStorageManager）
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

  /// 插件表 schema 缓存：pluginId → List<StorageTableDefinition>
  final Map<String, List<StorageTableDefinition>> _schemaCache = {};

  PluginStorageManager._internal(this._db);

  // ─── 表名辅助 ──────────────────────────────────────────────

  /// 生成数据库表名：plugin_{sanitized_uuid}__{table_name}
  static String dbTableName(String pluginId, String tableName) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}__$tableName';
  }

  /// 从数据库表名解析出 pluginId 前缀（用于查找属于某插件的所有表）
  static String _dbTablePrefix(String pluginId) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}__';
  }

  // ─── Schema 验证 ──────────────────────────────────────────

  /// 验证请求的表名是否在插件的注册 schema 中
  bool _isValidTable(String pluginId, String tableName) {
    final tables = _schemaCache[pluginId];
    if (tables == null) return false;
    return tables.any((t) => t.name == tableName);
  }

  /// 获取表的列定义
  StorageTableDefinition? _getTableDef(String pluginId, String tableName) {
    final tables = _schemaCache[pluginId];
    if (tables == null) return null;
    for (final t in tables) {
      if (t.name == tableName) return t;
    }
    return null;
  }

  /// 验证列名是否在表定义中（包括 _id）
  bool _isValidColumn(StorageTableDefinition tableDef, String columnName) {
    if (columnName == '_id') return true;
    return tableDef.columns.any((c) => c.name == columnName);
  }

  /// 获取列的类型定义
  StorageColumnDefinition? _getColumnDef(
      StorageTableDefinition tableDef, String columnName) {
    for (final c in tableDef.columns) {
      if (c.name == columnName) return c;
    }
    return null;
  }

  // ─── 表管理 ──────────────────────────────────────────────

  /// 确保插件的所有存储表存在（幂等，可在每次插件加载时调用）
  ///
  /// Schema 变更策略（尽可能保留已有数据）：
  /// - 新增列 → ALTER TABLE ADD COLUMN（旧数据保留，新列为 NULL）
  /// - 删除列 → 不做处理（旧列留在表中，但 CRUD 时自动忽略）
  /// - 列类型变更 → DROP 并重建（不可兼容的冲突）
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
          // schema 缓存中不包含这些列，CRUD 操作会自动忽略它们
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

  /// 检查现有表结构是否已满足期望 schema（无需任何迁移操作）
  ///
  /// 返回 true 的条件：期望的每一列都已存在于表中且类型相同。
  /// 现有表中多出的列（已从 schema 中移除）不影响判定。
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

  /// 注册插件的 schema（不创建表，仅缓存，用于 handler 验证）
  void registerSchema(String pluginId, List<StorageTableDefinition> tables) {
    _schemaCache[pluginId] = tables;
  }

  // ─── CRUD 操作 ──────────────────────────────────────────

  /// 插入一行或多行数据
  ///
  /// [rows] 可以是单个 Map 或 List<Map>
  /// 返回插入的行数
  Future<int> insert(
      String pluginId, String tableName, List<Map<String, dynamic>> rows) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = dbTableName(pluginId, tableName);
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

  /// 查询数据
  ///
  /// [where] 等值匹配条件
  /// [orderBy] 排序（如 "created_at DESC"）
  /// [limit] 限制返回行数
  /// [offset] 偏移
  Future<List<Map<String, dynamic>>> query(
    String pluginId,
    String tableName, {
    Map<String, dynamic>? where,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final fullName = dbTableName(pluginId, tableName);
    final tableDef = _getTableDef(pluginId, tableName);

    // 如果 schema 已注册，使用验证模式；否则使用宽松模式（用于设置页查看数据）
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

    // 宽松模式：无 schema 缓存，直接查询（不做列验证和 boolean 转换）
    // 先检查表是否存在
    final tableExists = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [fullName],
    );
    if (tableExists.isEmpty) return [];

    final _safeNameRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

    String sql = 'SELECT * FROM $fullName';
    List<Object?>? args;

    if (where != null && where.isNotEmpty) {
      final clauses = <String>[];
      args = <Object?>[];
      for (final entry in where.entries) {
        if (!_safeNameRegex.hasMatch(entry.key)) {
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
        if (!_safeNameRegex.hasMatch(colName)) {
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

  /// 更新数据
  ///
  /// [values] 要更新的列值
  /// [where] 匹配条件
  /// 返回更新的行数
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
    final fullName = dbTableName(pluginId, tableName);

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

  /// 删除数据
  ///
  /// [where] 匹配条件，为 null 或空则删除全部
  /// 返回删除的行数
  Future<int> delete(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = dbTableName(pluginId, tableName);

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

  /// 计数
  Future<int> count(
    String pluginId,
    String tableName,
    Map<String, dynamic>? where,
  ) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final tableDef = _getTableDef(pluginId, tableName)!;
    final fullName = dbTableName(pluginId, tableName);

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

  /// 清空表
  Future<void> clear(String pluginId, String tableName) async {
    if (!_isValidTable(pluginId, tableName)) {
      throw ArgumentError('Invalid table "$tableName" for plugin $pluginId');
    }

    final fullName = dbTableName(pluginId, tableName);
    await _db.delete(fullName);
  }

  // ─── 统计方法 ──────────────────────────────────────────

  /// 获取插件所有表的数据大小（字节，近似值）
  Future<int> getStorageSize(String pluginId) async {
    final tableNames = await getTableNames(pluginId);
    int totalSize = 0;

    for (final name in tableNames) {
      try {
        // 获取表的列信息
        final columnsInfo = await _db.rawQuery('PRAGMA table_info($name)');
        final textColumns = <String>[];
        for (final col in columnsInfo) {
          final colName = col['name'] as String;
          if (colName == '_id') continue;
          textColumns.add(colName);
        }

        if (textColumns.isEmpty) continue;

        // 对每列求 LENGTH 之和
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

  /// 获取插件所有表的总行数
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

  /// 获取插件的所有数据库表名（全名）
  Future<List<String>> getTableNames(String pluginId) async {
    final prefix = _dbTablePrefix(pluginId);
    final tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?",
      ['$prefix%'],
    );
    return tables.map((r) => r['name'] as String).toList();
  }

  /// 获取插件的所有表名（短名，不含前缀）
  Future<List<String>> getShortTableNames(String pluginId) async {
    final prefix = _dbTablePrefix(pluginId);
    final fullNames = await getTableNames(pluginId);
    return fullNames.map((n) => n.substring(prefix.length)).toList();
  }

  /// 获取所有有存储表的插件 ID
  Future<List<String>> getAllPluginIds() async {
    try {
      final tables = await _db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'plugin_%'",
      );

      final pluginIds = <String>{};
      for (final row in tables) {
        final name = row['name'] as String;
        // 格式：plugin_{sanitized_uuid}__{table_name}
        final doubleUnderscoreIdx = name.indexOf('__');
        if (doubleUnderscoreIdx > 7) {
          // "plugin_" 是 7 个字符
          final sanitizedId = name.substring(7, doubleUnderscoreIdx);
          // 还原 UUID 格式：8-4-4-4-12
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

  /// 从 sanitized UUID (下划线分隔) 还原为标准 UUID 格式
  static String? _restoreUuid(String sanitized) {
    // sanitized: 019e015b_5acf_7356_9759_7e68435a8ba9
    // 需要还原为: 019e015b-5acf-7356-9759-7e68435a8ba9
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

  // ─── 内部辅助 ──────────────────────────────────────────

  /// 将行数据 sanitize：只保留表定义中的列，并转换 boolean
  Map<String, dynamic> _sanitizeRow(
      StorageTableDefinition tableDef, Map<String, dynamic> row) {
    final result = <String, dynamic>{};
    for (final entry in row.entries) {
      // _id 允许在 update 的 where 中使用，但不应在 insert 中出现
      if (entry.key == '_id') continue;

      final colDef = _getColumnDef(tableDef, entry.key);
      if (colDef == null) continue; // 忽略未定义的列

      result[entry.key] = _convertValueToDb(colDef, entry.value);
    }
    return result;
  }

  /// 将 JS 值转换为数据库存储值
  dynamic _convertValueToDb(StorageColumnDefinition colDef, dynamic value) {
    if (value == null) return null;
    if (colDef.type == 'boolean') {
      // JS: true/false → DB: 1/0
      if (value is bool) return value ? 1 : 0;
      if (value is int) return value;
      if (value is String) return value.toLowerCase() == 'true' ? 1 : 0;
      return 0;
    }
    return value;
  }

  /// 将数据库行转换为 JS 可用的 Map（boolean 列 0/1 → true/false）
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

  /// 构建 WHERE 子句（参数化）
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

  /// 验证并清理 orderBy 字符串
  ///
  /// 只允许 "column_name ASC/DESC" 格式，多列用逗号分隔
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

  // ─── 隐式输出表 ──────────────────────────────────────────

  /// 已确保输出表存在的插件 ID 缓存（避免重复执行 CREATE TABLE）
  final Set<String> _outputsTableEnsured = {};

  /// 生成输出表的数据库全名
  static String _outputsTableName(String pluginId) {
    final sanitizedId = pluginId.replaceAll('-', '_');
    return 'plugin_${sanitizedId}____rc_outputs';
  }

  /// 确保输出表存在（幂等，同一会话内仅执行一次）
  Future<void> _ensureOutputsTable(String pluginId) async {
    if (_outputsTableEnsured.contains(pluginId)) return;
    final tableName = _outputsTableName(pluginId);
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        name TEXT PRIMARY KEY,
        type TEXT,
        value TEXT,
        updated_at TEXT
      )
    ''');
    _outputsTableEnsured.add(pluginId);
  }

  /// 写入或更新一个输出值（upsert）
  ///
  /// 输出表由宿主自动管理，插件通过 `RainCurtain.setOutput(name, value)` 调用。
  Future<void> upsertOutput(String pluginId, String name, dynamic value) async {
    await _ensureOutputsTable(pluginId);
    final tableName = _outputsTableName(pluginId);

    // 序列化值
    String? serializedValue;
    String type;
    if (value == null) {
      type = 'null';
      serializedValue = null;
    } else if (value is bool) {
      type = 'boolean';
      serializedValue = value.toString();
    } else if (value is num) {
      type = 'number';
      serializedValue = value.toString();
    } else if (value is String) {
      type = 'string';
      serializedValue = value;
    } else if (value is List || value is Map) {
      type = value is List ? 'array' : 'object';
      serializedValue = jsonEncode(value);
    } else {
      type = 'string';
      serializedValue = value.toString();
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await _db.rawInsert('''
      INSERT OR REPLACE INTO $tableName (name, type, value, updated_at)
      VALUES (?, ?, ?, ?)
    ''', [name, type, serializedValue, now]);
  }

  /// 获取插件的所有输出值
  Future<Map<String, dynamic>> getOutputs(String pluginId) async {
    final tableName = _outputsTableName(pluginId);

    // 检查表是否存在
    final existing = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    if (existing.isEmpty) return {};

    final rows = await _db.query(tableName);
    final outputs = <String, dynamic>{};
    for (final row in rows) {
      final name = row['name'] as String;
      final type = row['type'] as String?;
      final rawValue = row['value'] as String?;

      if (rawValue == null || type == 'null') {
        outputs[name] = null;
      } else if (type == 'boolean') {
        outputs[name] = rawValue == 'true';
      } else if (type == 'number') {
        outputs[name] = num.tryParse(rawValue) ?? rawValue;
      } else if (type == 'array' || type == 'object') {
        try {
          outputs[name] = jsonDecode(rawValue);
        } catch (_) {
          outputs[name] = rawValue;
        }
      } else {
        outputs[name] = rawValue;
      }
    }
    return outputs;
  }
}
