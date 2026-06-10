import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../../models/plugin_manager.dart';
import '../../../models/plugin_data_manager.dart';
import '../../../models/pool_manager.dart';
import '../../../models/variable_pool_manager.dart';

class RainCurtainStorageHandler {
  static String generateJS() {
    return '''
    // ========== 结构化存储 API ==========
    storage: {
      insert: async function(table, rows) {
        try {
          return await _call('rc_storage_insert', { table, rows: Array.isArray(rows) ? rows : [rows] });
        } catch (e) {
          console.error('RainCurtain.storage.insert error:', e);
          return { insertedCount: 0 };
        }
      },
      
      query: async function(table, options) {
        try {
          return await _call('rc_storage_query', { table, options: options || {} });
        } catch (e) {
          console.error('RainCurtain.storage.query error:', e);
          return [];
        }
      },
      
      update: async function(table, values, where) {
        try {
          return await _call('rc_storage_update', { table, values, where: where || null });
        } catch (e) {
          console.error('RainCurtain.storage.update error:', e);
          return { updatedCount: 0 };
        }
      },
      
      delete: async function(table, where) {
        try {
          return await _call('rc_storage_delete', { table, where: where || null });
        } catch (e) {
          console.error('RainCurtain.storage.delete error:', e);
          return { deletedCount: 0 };
        }
      },
      
      count: async function(table, where) {
        try {
          return await _call('rc_storage_count', { table, where: where || null });
        } catch (e) {
          console.error('RainCurtain.storage.count error:', e);
          return 0;
        }
      },
      
      clear: async function(table) {
        try {
          await _call('rc_storage_clear', { table });
        } catch (e) {
          console.error('RainCurtain.storage.clear error:', e);
        }
      }
    },
    ''';
  }

  static void register(
    InAppWebViewController controller, {
    required BuildContext context,
    required LocalPlugin plugin,
    String? poolId,
    String? poolPluginId,
  }) {
    // ========== 结构化存储 API Handlers ==========

    // 插入数据
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_insert',
      callback: (args) async {
        if (args.isEmpty) return {'insertedCount': 0};

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        final rowsRaw = data['rows'] as List?;
        if (table == null || rowsRaw == null) return {'insertedCount': 0};

        final rows = rowsRaw
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();

        // 溯流模式输出拦截：检查每行数据中的 key 是否匹配 outputMappings
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null) {
            for (final row in rows) {
              for (final entry in row.entries) {
                final variableName = pp.outputMappings[entry.key];
                if (variableName != null) {
                  final variablePoolManager = context.read<VariablePoolManager>();
                  final type = _inferType(entry.value);
                  await variablePoolManager.setVariable(
                    poolId,
                    variableName,
                    type,
                    entry.value,
                    sourcePluginId: plugin.id,
                  );
                }
              }
            }
          }
        }

        if (!context.mounted) return {'insertedCount': 0};
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return {'insertedCount': 0};

        try {
          final count = await dataManager.pluginStorageManager
              .insert(plugin.id, table, rows)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_insert: DB timeout'),
              );
          return {'insertedCount': count};
        } catch (e) {
          debugPrint('rc_storage_insert error: $e');
          return {'insertedCount': 0, 'error': e.toString()};
        }
      },
    );

    // 查询数据
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_query',
      callback: (args) async {
        if (args.isEmpty) return [];

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        if (table == null) return [];

        final options = data['options'] as Map<dynamic, dynamic>? ?? {};
        final where = options['where'] != null
            ? Map<String, dynamic>.from(options['where'] as Map)
            : null;
        final orderBy = options['orderBy'] as String?;
        final limit = options['limit'] as int?;
        final offset = options['offset'] as int?;

        // 溯流模式输入拦截：检查 where 中的 key 是否匹配 inputMappings
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null && where != null) {
            for (final key in where.keys.toList()) {
              final variableName = pp.inputMappings[key];
              if (variableName != null) {
                final variablePoolManager = context.read<VariablePoolManager>();
                final value = await variablePoolManager.getVariable(poolId, variableName);
                if (value != null) {
                  where[key] = value;
                }
              }
            }
          }
        }

        if (!context.mounted) return [];
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return [];

        try {
          return await dataManager.pluginStorageManager
              .query(
                plugin.id,
                table,
                where: where,
                orderBy: orderBy,
                limit: limit,
                offset: offset,
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_query: DB timeout'),
              );
        } catch (e) {
          debugPrint('rc_storage_query error: $e');
          return [];
        }
      },
    );

    // 更新数据
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_update',
      callback: (args) async {
        if (args.isEmpty) return {'updatedCount': 0};

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        final values = data['values'] != null
            ? Map<String, dynamic>.from(data['values'] as Map)
            : null;
        final where = data['where'] != null
            ? Map<String, dynamic>.from(data['where'] as Map)
            : null;
        if (table == null || values == null) return {'updatedCount': 0};

        // 溯流模式输出拦截：检查 values 中的 key 是否匹配 outputMappings
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null) {
            for (final entry in values.entries) {
              final variableName = pp.outputMappings[entry.key];
              if (variableName != null) {
                final variablePoolManager = context.read<VariablePoolManager>();
                final type = _inferType(entry.value);
                await variablePoolManager.setVariable(
                  poolId,
                  variableName,
                  type,
                  entry.value,
                  sourcePluginId: plugin.id,
                );
              }
            }
          }
        }

        if (!context.mounted) return {'updatedCount': 0};
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return {'updatedCount': 0};

        try {
          final count = await dataManager.pluginStorageManager
              .update(plugin.id, table, values, where)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_update: DB timeout'),
              );
          return {'updatedCount': count};
        } catch (e) {
          debugPrint('rc_storage_update error: $e');
          return {'updatedCount': 0, 'error': e.toString()};
        }
      },
    );

    // 删除数据
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_delete',
      callback: (args) async {
        if (args.isEmpty) return {'deletedCount': 0};

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        final where = data['where'] != null
            ? Map<String, dynamic>.from(data['where'] as Map)
            : null;
        if (table == null) return {'deletedCount': 0};

        // 溯流模式输入拦截：检查 where 中的 key 是否匹配 inputMappings
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null && where != null) {
            for (final key in where.keys.toList()) {
              final variableName = pp.inputMappings[key];
              if (variableName != null) {
                final variablePoolManager = context.read<VariablePoolManager>();
                final value = await variablePoolManager.getVariable(poolId, variableName);
                if (value != null) {
                  where[key] = value;
                }
              }
            }
          }
        }

        if (!context.mounted) return {'deletedCount': 0};
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return {'deletedCount': 0};

        try {
          final count = await dataManager.pluginStorageManager
              .delete(plugin.id, table, where)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_delete: DB timeout'),
              );
          return {'deletedCount': count};
        } catch (e) {
          debugPrint('rc_storage_delete error: $e');
          return {'deletedCount': 0, 'error': e.toString()};
        }
      },
    );

    // 计数
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_count',
      callback: (args) async {
        if (args.isEmpty) return 0;

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        final where = data['where'] != null
            ? Map<String, dynamic>.from(data['where'] as Map)
            : null;
        if (table == null) return 0;

        // 溯流模式输入拦截：检查 where 中的 key 是否匹配 inputMappings
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null && where != null) {
            for (final key in where.keys.toList()) {
              final variableName = pp.inputMappings[key];
              if (variableName != null) {
                final variablePoolManager = context.read<VariablePoolManager>();
                final value = await variablePoolManager.getVariable(poolId, variableName);
                if (value != null) {
                  where[key] = value;
                }
              }
            }
          }
        }

        if (!context.mounted) return 0;
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return 0;

        try {
          return await dataManager.pluginStorageManager
              .count(plugin.id, table, where)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_count: DB timeout'),
              );
        } catch (e) {
          debugPrint('rc_storage_count error: $e');
          return 0;
        }
      },
    );

    // 清空表
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_clear',
      callback: (args) async {
        if (args.isEmpty) return;

        final data = args[0] as Map<dynamic, dynamic>;
        final table = data['table'] as String?;
        if (table == null) return;

        if (!context.mounted) return;
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return;

        try {
          await dataManager.pluginStorageManager
              .clear(plugin.id, table)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_clear: DB timeout'),
              );
        } catch (e) {
          debugPrint('rc_storage_clear error: $e');
        }
      },
    );
  }

  /// 推断值的 JS 类型名
  static String _inferType(dynamic value) {
    if (value == null) return 'string';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    return 'string';
  }
}
