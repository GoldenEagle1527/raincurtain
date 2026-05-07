import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pool.dart';
import 'pool_plugin.dart';

class PoolManager extends ChangeNotifier {
  List<Pool> _pools = [];
  final Map<String, List<PoolPlugin>> _poolPlugins = {}; // poolId -> plugins
  bool _isInit = false;

  List<Pool> get pools => List.unmodifiable(_pools);
  bool get isInit => _isInit;

  PoolManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadPools();
      await _loadAllPoolPlugins();
    } catch (e) {
      debugPrint('PoolManager init failed: $e');
    } finally {
      _isInit = true;
      notifyListeners();
    }
  }

  Future<void> _loadPools() async {
    final prefs = await SharedPreferences.getInstance();
    final poolsJson = prefs.getString('pools');
    if (poolsJson != null) {
      final List<dynamic> decoded = jsonDecode(poolsJson);
      _pools = decoded
          .map((e) => Pool.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  }

  Future<void> _savePools() async {
    final prefs = await SharedPreferences.getInstance();
    final poolsJson = jsonEncode(_pools.map((e) => e.toJson()).toList());
    await prefs.setString('pools', poolsJson);
  }

  Future<void> _loadAllPoolPlugins() async {
    final prefs = await SharedPreferences.getInstance();
    for (final pool in _pools) {
      final key = 'pool_plugins_${pool.id}';
      final json = prefs.getString(key);
      if (json != null) {
        final List<dynamic> decoded = jsonDecode(json);
        _poolPlugins[pool.id] = decoded
            .map((e) =>
                PoolPlugin.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        _poolPlugins[pool.id] = [];
      }
    }
  }

  Future<void> _savePoolPlugins(String poolId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pool_plugins_$poolId';
    final plugins = _poolPlugins[poolId] ?? [];
    final json = jsonEncode(plugins.map((e) => e.toJson()).toList());
    await prefs.setString(key, json);
  }

  // ========== Pool CRUD ==========

  Future<Pool> createPool(String name) async {
    final pool = Pool(name: name);
    _pools.add(pool);
    _poolPlugins[pool.id] = [];
    await _savePools();
    notifyListeners();
    return pool;
  }

  Future<void> updatePool(String poolId, String newName) async {
    final index = _pools.indexWhere((p) => p.id == poolId);
    if (index != -1) {
      _pools[index] = _pools[index].copyWith(name: newName);
      await _savePools();
      notifyListeners();
    }
  }

  Future<void> deletePool(String poolId) async {
    _pools.removeWhere((p) => p.id == poolId);
    _poolPlugins.remove(poolId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pool_plugins_$poolId');

    await _savePools();
    notifyListeners();
  }

  Pool? getPoolById(String poolId) {
    try {
      return _pools.firstWhere((p) => p.id == poolId);
    } catch (_) {
      return null;
    }
  }

  // ========== PoolPlugin CRUD ==========

  List<PoolPlugin> getPoolPlugins(String poolId) {
    final plugins = List<PoolPlugin>.from(_poolPlugins[poolId] ?? []);
    plugins.sort((a, b) => a.order.compareTo(b.order));
    return plugins;
  }

  Future<PoolPlugin> addPluginToPool(String poolId, String pluginId) async {
    final plugins = _poolPlugins[poolId] ?? [];
    final maxOrder = plugins.isEmpty
        ? 0
        : plugins.map((p) => p.order).reduce((a, b) => a > b ? a : b);

    final poolPlugin = PoolPlugin(
      pluginId: pluginId,
      order: maxOrder + 1,
    );

    plugins.add(poolPlugin);
    _poolPlugins[poolId] = plugins;

    await _savePoolPlugins(poolId);
    notifyListeners();
    return poolPlugin;
  }

  Future<void> removePluginFromPool(String poolId, String poolPluginId) async {
    final plugins = _poolPlugins[poolId] ?? [];
    plugins.removeWhere((p) => p.id == poolPluginId);
    _poolPlugins[poolId] = plugins;

    await _savePoolPlugins(poolId);
    notifyListeners();
  }

  Future<void> reorderPlugins(
      String poolId, int oldIndex, int newIndex) async {
    final plugins = getPoolPlugins(poolId); // sorted
    if (oldIndex < 0 ||
        oldIndex >= plugins.length ||
        newIndex < 0 ||
        newIndex >= plugins.length) return;

    final item = plugins.removeAt(oldIndex);
    plugins.insert(newIndex, item);

    // Reassign orders based on new positions
    for (int i = 0; i < plugins.length; i++) {
      plugins[i] = plugins[i].copyWith(order: i + 1);
    }

    _poolPlugins[poolId] = plugins;
    await _savePoolPlugins(poolId);
    notifyListeners();
  }

  Future<void> updatePluginMappings(
    String poolId,
    String poolPluginId,
    Map<String, String> inputMappings,
    Map<String, String> outputMappings,
  ) async {
    final plugins = _poolPlugins[poolId] ?? [];
    final index = plugins.indexWhere((p) => p.id == poolPluginId);
    if (index != -1) {
      plugins[index] = plugins[index].copyWith(
        inputMappings: inputMappings,
        outputMappings: outputMappings,
      );
      _poolPlugins[poolId] = plugins;
      await _savePoolPlugins(poolId);
      notifyListeners();
    }
  }

  PoolPlugin? getPoolPluginById(String poolId, String poolPluginId) {
    final plugins = _poolPlugins[poolId] ?? [];
    try {
      return plugins.firstWhere((p) => p.id == poolPluginId);
    } catch (_) {
      return null;
    }
  }
}
