import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'variable.dart';

class VariablePoolManager extends ChangeNotifier {
  // poolId -> {variableName -> Variable}
  final Map<String, Map<String, Variable>> _pools = {};
  // Track which pools have been loaded from storage
  final Set<String> _loadedPools = {};
  bool _isInit = false;

  late Directory _rootDir;

  bool get isInit => _isInit;

  VariablePoolManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      _rootDir = Directory(p.join(supportDir.path, 'RainCurtainPoolsData'));
      await _rootDir.create(recursive: true);

      _isInit = true;
      notifyListeners();

      debugPrint('VariablePoolManager initialized at: ${_rootDir.path}');
    } catch (e, stackTrace) {
      debugPrint('VariablePoolManager init failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isInit = false;
    }
  }

  // ========== Path helpers ==========

  Directory _getPoolDir(String poolId) {
    return Directory(p.join(_rootDir.path, poolId));
  }

  File _getPluginDataFile(String poolId, String pluginId) {
    return File(p.join(_rootDir.path, poolId, '$pluginId.json'));
  }

  // ========== Loading ==========

  Future<void> _loadPoolVariables(String poolId) async {
    if (_loadedPools.contains(poolId)) return;

    final poolDir = _getPoolDir(poolId);
    final Map<String, Variable> merged = {};

    try {
      if (await poolDir.exists()) {
        final entities = await poolDir.list().toList();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final content = await entity.readAsString();
              final jsonData = jsonDecode(content) as Map<String, dynamic>;
              final data = jsonData['data'] as Map<String, dynamic>? ?? {};

              for (final entry in data.entries) {
                final variable = Variable.fromJson(
                    Map<String, dynamic>.from(entry.value as Map));
                // Last-write-wins: keep the variable with the latest updatedAt
                if (!merged.containsKey(entry.key) ||
                    variable.updatedAt
                        .isAfter(merged[entry.key]!.updatedAt)) {
                  merged[entry.key] = variable;
                }
              }
            } catch (e) {
              debugPrint(
                  'Failed to load pool variable file ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load pool variables for $poolId: $e');
    }

    _pools[poolId] = merged;
    _loadedPools.add(poolId);
  }

  // ========== Saving ==========

  /// Save a single variable to its corresponding plugin data file.
  Future<void> _saveVariableToFile(
      String poolId, Variable variable) async {
    final pluginId = variable.sourcePluginId ?? '_manual';
    final file = _getPluginDataFile(poolId, pluginId);

    try {
      final poolDir = _getPoolDir(poolId);
      if (!await poolDir.exists()) {
        await poolDir.create(recursive: true);
      }

      // Load existing file data
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final jsonData = jsonDecode(content) as Map<String, dynamic>;
          data = Map<String, dynamic>.from(jsonData['data'] as Map? ?? {});
        } catch (e) {
          debugPrint('Failed to read existing file, overwriting: $e');
        }
      }

      // Update/add the variable
      data[variable.name] = variable.toJson();

      final jsonData = {
        'data': data,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(jsonData), flush: true);
    } catch (e) {
      debugPrint(
          'Failed to save variable ${variable.name} for pool $poolId: $e');
    }
  }

  /// Remove a variable from its plugin data file.
  Future<void> _removeVariableFromFile(
      String poolId, String variableName, String? sourcePluginId) async {
    final pluginId = sourcePluginId ?? '_manual';
    final file = _getPluginDataFile(poolId, pluginId);

    try {
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      final data =
          Map<String, dynamic>.from(jsonData['data'] as Map? ?? {});

      data.remove(variableName);

      if (data.isEmpty) {
        await file.delete();
      } else {
        final updated = {
          'data': data,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        await file.writeAsString(jsonEncode(updated), flush: true);
      }
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

    await _saveVariableToFile(poolId, variable);
    notifyListeners();
  }

  Future<void> deleteVariable(String poolId, String variableName) async {
    await _loadPoolVariables(poolId);
    final variable = _pools[poolId]?[variableName];
    if (variable != null) {
      _pools[poolId]?.remove(variableName);
      await _removeVariableFromFile(
          poolId, variableName, variable.sourcePluginId);
      notifyListeners();
    }
  }

  Future<void> clearPool(String poolId) async {
    _pools[poolId] = {};
    _loadedPools.remove(poolId);

    try {
      final poolDir = _getPoolDir(poolId);
      if (await poolDir.exists()) {
        await poolDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to clear pool directory for $poolId: $e');
    }

    notifyListeners();
  }

  /// Delete all data produced by a specific plugin in a pool.
  Future<void> deletePluginData(String poolId, String pluginId) async {
    await _loadPoolVariables(poolId);

    // Remove from in-memory cache
    _pools[poolId]?.removeWhere((_, v) => (v.sourcePluginId ?? '_manual') == pluginId);

    // Delete the plugin data file
    try {
      final file = _getPluginDataFile(poolId, pluginId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
          'Failed to delete plugin data file for $pluginId in pool $poolId: $e');
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
