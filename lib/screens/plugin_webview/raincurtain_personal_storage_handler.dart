import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../models/plugin_manager.dart';

class RainCurtainPersonalStorageHandler {
  static String generateJS() {
    return '''
    // ========== 专属物理目录存储 API ==========
    personalStorage: {
      writeText: async function(path, text) {
        try {
          return await _call('rc_personal_write_text', { path: path, text: text });
        } catch (e) {
          console.error('RainCurtain.personalStorage.writeText error:', e);
          return { success: false, error: e.toString() };
        }
      },
      writeBinary: async function(path, base64Data) {
        try {
          return await _call('rc_personal_write_binary', { path: path, data: base64Data });
        } catch (e) {
          console.error('RainCurtain.personalStorage.writeBinary error:', e);
          return { success: false, error: e.toString() };
        }
      },
      readText: async function(path) {
        try {
          return await _call('rc_personal_read_text', { path: path });
        } catch (e) {
          console.error('RainCurtain.personalStorage.readText error:', e);
          return null;
        }
      },
      readBinary: async function(path) {
        try {
          return await _call('rc_personal_read_binary', { path: path });
        } catch (e) {
          console.error('RainCurtain.personalStorage.readBinary error:', e);
          return null;
        }
      },
      delete: async function(path) {
        try {
          return await _call('rc_personal_delete', { path: path });
        } catch (e) {
          console.error('RainCurtain.personalStorage.delete error:', e);
          return { success: false, error: e.toString() };
        }
      },
      list: async function(path) {
        try {
          return await _call('rc_personal_list', { path: path || "" });
        } catch (e) {
          console.error('RainCurtain.personalStorage.list error:', e);
          return [];
        }
      },
      exists: async function(path) {
        try {
          return await _call('rc_personal_exists', { path: path });
        } catch (e) {
          console.error('RainCurtain.personalStorage.exists error:', e);
          return false;
        }
      }
    },
    ''';
  }

  static void register(
    InAppWebViewController controller, {
    required LocalPlugin plugin,
  }) {
    // ========== 专属物理目录存储 API Handlers ==========

    // 写入文本
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_write_text',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'success': false, 'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          final text = data['text'] as String?;
          if (relativePath == null || relativePath.isEmpty) {
            return {'success': false, 'error': 'Path is empty'};
          }
          if (text == null) {
            return {'success': false, 'error': 'Text content is null'};
          }

          final file = (await _getSafeEntity(plugin.id, relativePath)) as File;
          await file.parent.create(recursive: true);
          await file.writeAsString(text);
          return {'success': true};
        } catch (e) {
          debugPrint('rc_personal_write_text error: $e');
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    // 写入二进制
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_write_binary',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'success': false, 'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          final base64Data = data['data'] as String?;
          if (relativePath == null || relativePath.isEmpty) {
            return {'success': false, 'error': 'Path is empty'};
          }
          if (base64Data == null) {
            return {'success': false, 'error': 'Data is null'};
          }

          final bytes = base64Decode(base64Data);
          final file = (await _getSafeEntity(plugin.id, relativePath)) as File;
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          return {'success': true};
        } catch (e) {
          debugPrint('rc_personal_write_binary error: $e');
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    // 读取文本
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_read_text',
      callback: (args) async {
        try {
          if (args.isEmpty) return null;
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          if (relativePath == null || relativePath.isEmpty) return null;

          final file = (await _getSafeEntity(plugin.id, relativePath)) as File;
          if (!await file.exists()) return null;
          return await file.readAsString();
        } catch (e) {
          debugPrint('rc_personal_read_text error: $e');
          return null;
        }
      },
    );

    // 读取二进制
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_read_binary',
      callback: (args) async {
        try {
          if (args.isEmpty) return null;
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          if (relativePath == null || relativePath.isEmpty) return null;

          final file = (await _getSafeEntity(plugin.id, relativePath)) as File;
          if (!await file.exists()) return null;
          final bytes = await file.readAsBytes();
          return base64Encode(bytes);
        } catch (e) {
          debugPrint('rc_personal_read_binary error: $e');
          return null;
        }
      },
    );

    // 删除文件或目录
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_delete',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'success': false, 'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          if (relativePath == null || relativePath.isEmpty) {
            return {'success': false, 'error': 'Path is empty'};
          }

          final entity = await _getSafeEntity(plugin.id, relativePath);
          if (await entity.exists()) {
            await entity.delete(recursive: true);
            return {'success': true};
          }
          return {'success': false, 'error': 'File or directory not found'};
        } catch (e) {
          debugPrint('rc_personal_delete error: $e');
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    // 列表目录内容
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_list',
      callback: (args) async {
        try {
          if (args.isEmpty) return [];
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String? ?? '';

          final dir = (await _getSafeEntity(plugin.id, relativePath, isDirectory: true)) as Directory;
          if (!await dir.exists()) return [];

          final supportDir = await getApplicationSupportDirectory();
          final rootDir = Directory(p.join(supportDir.path, 'RainCurtainPersonalStorage', plugin.id));

          final list = <Map<String, dynamic>>[];
          await for (final item in dir.list()) {
            final name = p.basename(item.path);
            final relPath = p.relative(item.path, from: rootDir.path).replaceAll('\\', '/');
            list.add({
              'name': name,
              'kind': item is Directory ? 'directory' : 'file',
              'path': relPath,
            });
          }
          return list;
        } catch (e) {
          debugPrint('rc_personal_list error: $e');
          return [];
        }
      },
    );

    // 检查是否存在
    controller.addJavaScriptHandler(
      handlerName: 'rc_personal_exists',
      callback: (args) async {
        try {
          if (args.isEmpty) return false;
          final data = args[0] as Map<dynamic, dynamic>;
          final relativePath = data['path'] as String?;
          if (relativePath == null || relativePath.isEmpty) return false;

          final entity = await _getSafeEntity(plugin.id, relativePath);
          return await entity.exists();
        } catch (e) {
          debugPrint('rc_personal_exists error: $e');
          return false;
        }
      },
    );
  }

  /// 获取插件专属的、安全的物理 File 或 Directory 实体，并确保不存在越界路径遍历
  static Future<FileSystemEntity> _getSafeEntity(String pluginId, String relativePath, {bool isDirectory = false}) async {
    final supportDir = await getApplicationSupportDirectory();
    final rootDir = Directory(p.join(supportDir.path, 'RainCurtainPersonalStorage', pluginId));
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    final targetPath = p.normalize(p.join(rootDir.path, relativePath));
    final canonicalRoot = p.canonicalize(rootDir.path);
    final canonicalTarget = p.canonicalize(targetPath);

    if (!p.isWithin(canonicalRoot, canonicalTarget) && canonicalTarget != canonicalRoot) {
      throw Exception('SecurityError: Path traversal attempt blocked.');
    }

    return isDirectory ? Directory(targetPath) : File(targetPath);
  }
}
