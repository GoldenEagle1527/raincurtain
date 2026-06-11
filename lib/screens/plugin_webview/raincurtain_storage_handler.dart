import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../../../models/plugin_manager.dart';
import '../../../models/plugin_data_manager.dart';


class RainCurtainStorageHandler {
  static String generateJS() {
    return '''
    // ========== 结构化存储 API ==========
    storage: {
      sql: async function(sqlStr, params) {
        try {
          return await _call('rc_storage_sql', { sql: sqlStr, params: params || [] });
        } catch (e) {
          console.error('RainCurtain.storage.sql error:', e);
          return { error: e.message || String(e) };
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

    // 原生 SQL 执行
    controller.addJavaScriptHandler(
      handlerName: 'rc_storage_sql',
      callback: (args) async {
        if (args.isEmpty) return {'error': 'No arguments'};

        final data = args[0] as Map<dynamic, dynamic>;
        final sql = data['sql'] as String?;
        final paramsRaw = data['params'] as List?;
        if (sql == null || sql.trim().isEmpty) {
          return {'error': 'SQL statement is required'};
        }

        final params = paramsRaw?.map((e) => e as Object?).toList() ?? <Object?>[];

        if (!context.mounted) return {'error': 'Context not mounted'};
        final dataManager = context.read<PluginDataManager>();
        if (!dataManager.isInit) return {'error': 'Storage not initialized'};

        try {
          return await dataManager.pluginStorageManager
              .executeSql(plugin.id, sql, params)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception('rc_storage_sql: DB timeout'),
              );
        } catch (e) {
          debugPrint('rc_storage_sql error: $e');
          return {'error': e.toString()};
        }
      },
    );
  }
}
