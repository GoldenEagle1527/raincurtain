import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PluginStorageOutputs {
  final Database _db;
  final Set<String> _outputsTableEnsured = {};

  PluginStorageOutputs(this._db);

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
