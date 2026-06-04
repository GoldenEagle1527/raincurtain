import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_manager.dart';
import '../../models/plugin_data_manager.dart';
import '../../models/pool_manager.dart';
import '../../models/variable_pool_manager.dart';

/// RainCurtain 核心 API 的 JS 生成和 Handler 注册
mixin RainCurtainApiMixin {
  /// 推断值的 JS 类型名
  String _inferType(dynamic value) {
    if (value == null) return 'string';
    if (value is bool) return 'boolean';
    if (value is num) return 'number';
    if (value is List) return 'array';
    if (value is Map) return 'object';
    return 'string';
  }

  /// 生成 RainCurtain API 注入 JS
  String generateRainCurtainAPI(String pluginId) {
    return '''
(function() {
  function _call(handler, args) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(handler, args);
  }

  window.RainCurtain = {
    // ========== 元数据 ==========
    pluginId: '$pluginId',
    
    // ========== 输入获取 ==========
    getInput: async function(name) {
      try {
        return await _call('rc_get_input', name);
      } catch (e) {
        console.error('RainCurtain.getInput error:', e);
        return null;
      }
    },
    
    // ========== 输出设置 ==========
    setOutput: async function(name, value) {
      try {
        return await _call('rc_set_output', { name: name, value: value });
      } catch (e) {
        console.error('RainCurtain.setOutput error:', e);
      }
    },
    
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
    }
  };
  
  // 标记 API 已就绪
  window.__raincurtain_ready__ = true;
  window.dispatchEvent(new Event('raincurtain:ready'));
})();
''';
  }

  /// 注册核心 API Handlers
  void registerApiHandlers(
    InAppWebViewController controller, {
    required BuildContext context,
    required LocalPlugin plugin,
    String? poolId,
    String? poolPluginId,
  }) {
    // ========== 输入获取 API Handler ==========
    controller.addJavaScriptHandler(
      handlerName: 'rc_get_input',
      callback: (args) async {
        if (args.isEmpty) return null;

        final inputName = args[0] as String?;
        if (inputName == null || inputName.isEmpty) return null;

        // 查找 manifest 中对应的 input 定义
        final inputs = plugin.manifest.inputs;
        final inputDef = inputs
            .where((i) => i.name == inputName)
            .firstOrNull;

        // 溯流模式：尝试从变量池获取映射的值
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null) {
            final variableName = pp.inputMappings[inputName];
            if (variableName != null) {
              final variablePoolManager = context.read<VariablePoolManager>();
              final value = await variablePoolManager.getVariable(
                  poolId, variableName);
              // 空字符串也视为无效值，回退到 manifest default
              if (value != null && value != '') return value;
            }
          }
        }

        // 回退到 manifest default
        return inputDef?.defaultValue;
      },
    );

    // ========== 输出设置 API Handler ==========
    controller.addJavaScriptHandler(
      handlerName: 'rc_set_output',
      callback: (args) async {
        if (args.isEmpty) return null;

        final data = args[0] as Map<dynamic, dynamic>;
        final name = data['name'] as String?;
        final value = data['value'];
        if (name == null || name.isEmpty) return null;

        // 验证 name 是否在 manifest outputs 中声明
        final outputs = plugin.manifest.outputs;
        final outputDef = outputs.where((o) => o.name == name).firstOrNull;
        if (outputDef == null) {
          debugPrint('rc_set_output: unknown output "$name" for plugin ${plugin.id}');
          return null;
        }

        // 1. 写入隐式 _outputs 表（upsert）
        if (!context.mounted) return null;
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return null;
        await dataManager.pluginStorageManager
            .upsertOutput(plugin.id, name, value)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception('rc_set_output: DB timeout'),
            );

        // 2. 溯流模式：检查 outputMappings 写入变量池
        if (poolId != null && poolPluginId != null && context.mounted) {
          final poolManager = context.read<PoolManager>();
          final pp = poolManager.getPoolPluginById(poolId, poolPluginId);
          if (pp != null) {
            final variableName = pp.outputMappings[name];
            if (variableName != null) {
              final variablePoolManager = context.read<VariablePoolManager>();
              final type = _inferType(value);
              await variablePoolManager.setVariable(
                poolId,
                variableName,
                type,
                value,
                sourcePluginId: plugin.id,
              );
            }
          }
        }

        return null;
      },
    );

    // ========== 结构化存储 API Handlers ==========

    // 插入数据 (带输出拦截：溯流模式下匹配 outputMappings 写变量池)
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

    // 查询数据 (带输入拦截：溯流模式下变量池优先)
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

    // 删除数据 (带输入拦截：溯流模式下变量池优先)
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

    // 计数 (带输入拦截：溯流模式下变量池优先)
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
}
