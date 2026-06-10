import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../../models/plugin_manager.dart';
import '../../../models/plugin_data_manager.dart';
import '../../../models/pool_manager.dart';
import '../../../models/variable_pool_manager.dart';

class RainCurtainCoreHandler {
  static String generateJS() {
    return '''
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
    ''';
  }

  static void register(
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
