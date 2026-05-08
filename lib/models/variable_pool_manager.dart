import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_manager.dart';
import 'variable.dart';

class VariablePoolManager extends ChangeNotifier {
  // poolId -> {variableName -> Variable}
  final Map<String, Map<String, Variable>> _pools = {};
  // Track which pools have been loaded from storage
  final Set<String> _loadedPools = {};
  bool _isInit = false;

  late Database _db;

  bool get isInit => _isInit;

  VariablePoolManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      _db = DatabaseManager.database;
      _isInit = true;
      notifyListeners();
      debugPrint('VariablePoolManager initialized (SQLite)');
    } catch (e, stackTrace) {
      debugPrint('VariablePoolManager init failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isInit = false;
    }
  }

  // ========== Loading ==========

  Future<void> _loadPoolVariables(String poolId) async {
    if (_loadedPools.contains(poolId)) return;

    final Map<String, Variable> merged = {};

    try {
      final rows = await _db.query(
        'pool_variables',
        where: 'pool_id = ?',
        whereArgs: [poolId],
      );

      for (final row in rows) {
        final valueStr = row['value'] as String?;
        dynamic value;
        if (valueStr != null) {
          try {
            value = jsonDecode(valueStr);
          } catch (_) {
            value = valueStr;
          }
        }

        final variable = Variable(
          name: row['variable_name'] as String,
          type: row['type'] as String,
          value: value,
          updatedAt: DateTime.parse(row['updated_at'] as String),
          sourcePluginId: row['source_plugin_id'] as String?,
        );
        merged[variable.name] = variable;
      }
    } catch (e) {
      debugPrint('Failed to load pool variables for $poolId: $e');
    }

    _pools[poolId] = merged;
    _loadedPools.add(poolId);
  }

  // ========== Saving ==========

  /// Save a single variable to the database.
  Future<void> _saveVariableToDb(String poolId, Variable variable) async {
    try {
      final valueEncoded =
          variable.value != null ? jsonEncode(variable.value) : null;

      await _db.insert(
        'pool_variables',
        {
          'pool_id': poolId,
          'variable_name': variable.name,
          'type': variable.type,
          'value': valueEncoded,
          'source_plugin_id': variable.sourcePluginId,
          'updated_at': variable.updatedAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint(
          'Failed to save variable ${variable.name} for pool $poolId: $e');
    }
  }

  /// Remove a variable from the database.
  Future<void> _removeVariableFromDb(
      String poolId, String variableName) async {
    try {
      await _db.delete(
        'pool_variables',
        where: 'pool_id = ? AND variable_name = ?',
        whereArgs: [poolId, variableName],
      );
    } catch (e) {
      debugPrint(
          'Failed to remove variable $variableName from pool $poolId: $e');
    }
  }

  // ========== Public API ==========

  Future<dynamic> getVariable(String poolId, String variableName) async {
    await _loadPoolVariables(poolId);
    return _pools[poolId]?[variableName]?.value;
  }

  Future<Variable?> getVariableObject(
      String poolId, String variableName) async {
    await _loadPoolVariables(poolId);
    return _pools[poolId]?[variableName];
  }

  Future<void> setVariable(
    String poolId,
    String variableName,
    String type,
    dynamic value, {
    String? sourcePluginId,
  }) async {
    await _loadPoolVariables(poolId);

    final variable = Variable(
      name: variableName,
      type: type,
      value: value,
      sourcePluginId: sourcePluginId,
    );

    _pools[poolId] ??= {};
    _pools[poolId]![variableName] = variable;

    await _saveVariableToDb(poolId, variable);
    notifyListeners();
  }

  Future<void> deleteVariable(String poolId, String variableName) async {
    await _loadPoolVariables(poolId);
    final variable = _pools[poolId]?[variableName];
    if (variable != null) {
      _pools[poolId]?.remove(variableName);
      await _removeVariableFromDb(poolId, variableName);
      notifyListeners();
    }
  }

  Future<void> clearPool(String poolId) async {
    _pools[poolId] = {};
    _loadedPools.remove(poolId);

    try {
      await _db.delete(
        'pool_variables',
        where: 'pool_id = ?',
        whereArgs: [poolId],
      );
    } catch (e) {
      debugPrint('Failed to clear pool data for $poolId: $e');
    }

    notifyListeners();
  }

  /// Delete all data produced by a specific plugin in a pool.
  Future<void> deletePluginData(String poolId, String pluginId) async {
    await _loadPoolVariables(poolId);

    // Remove from in-memory cache
    _pools[poolId]
        ?.removeWhere((_, v) => (v.sourcePluginId ?? '_manual') == pluginId);

    // Delete from database
    try {
      await _db.delete(
        'pool_variables',
        where: 'pool_id = ? AND source_plugin_id = ?',
        whereArgs: [poolId, pluginId],
      );
    } catch (e) {
      debugPrint(
          'Failed to delete plugin data for $pluginId in pool $poolId: $e');
    }

    notifyListeners();
  }

  /// Get all variables for a pool (loads from storage if needed, async)
  Future<Map<String, Variable>> getPoolVariablesAsync(String poolId) async {
    await _loadPoolVariables(poolId);
    return Map.from(_pools[poolId] ?? {});
  }

  /// Get all variables for a pool (returns cached, empty if not loaded)
  Map<String, Variable> getPoolVariables(String poolId) {
    return Map.from(_pools[poolId] ?? {});
  }

  List<Variable> getPoolVariablesList(String poolId) {
    final variables = _pools[poolId] ?? {};
    return variables.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Ensure a pool's variables are loaded into memory
  Future<void> ensureLoaded(String poolId) async {
    await _loadPoolVariables(poolId);
  }
}
