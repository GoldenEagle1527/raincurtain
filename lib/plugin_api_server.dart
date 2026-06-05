import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'main.dart' show sandboxServerPort;
import 'models/plugin_manager.dart';

/// 独立的 HTTP API 服务器，供外部工具（Electron 创建器、卸载脚本等）调用。
///
/// 监听 `127.0.0.1:19280`，提供插件管理 RESTful API。
/// 所有数据库操作通过 [PluginManager] 统一执行，杜绝并发冲突。
class PluginApiServer {
  static const int kPort = 19280;
  static const String kApiVersion = '1.0.0';
  static const String kAppVersion = '1.2.6+2';

  final PluginManager pluginManager;
  HttpServer? _server;

  PluginApiServer(this.pluginManager);

  /// 路由正则：匹配 /api/plugins/{uuid}（可选后缀 /{action}）
  static final RegExp _pluginIdPattern = RegExp(
    r'^/api/plugins/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:/(\w+))?$',
  );

  /// 启动 API 服务器。
  ///
  /// 返回是否启动成功。端口冲突时返回 false 不抛异常，不阻塞应用启动。
  Future<bool> start() async {
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        kPort,
        shared: false,
      );
      _server!.listen(_handleRequest);
      debugPrint('PluginApiServer listening on http://127.0.0.1:$kPort');
      return true;
    } catch (e) {
      debugPrint('PluginApiServer failed to start on port $kPort: $e');
      return false;
    }
  }

  /// 关闭服务器。
  Future<void> close() async {
    await _server?.close();
    _server = null;
  }

  // ─── 请求分发 ──────────────────────────────────────────

  void _handleRequest(HttpRequest req) async {
    try {
      // CORS 预检
      if (req.method == 'OPTIONS') {
        _setCorsHeaders(req.response);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      final path = req.uri.path;

      // 静态路由
      if (path == '/api/health' && req.method == 'GET') {
        await _handleHealth(req);
        return;
      }
      if (path == '/api/plugins' && req.method == 'GET') {
        await _handleListPlugins(req);
        return;
      }
      if (path == '/api/plugins/register' && req.method == 'POST') {
        await _handleRegisterPlugin(req);
        return;
      }
      if (path == '/api/plugins/install' && req.method == 'POST') {
        await _handleInstallPlugin(req);
        return;
      }
      if (path == '/api/plugins/reload-all' && req.method == 'POST') {
        await _handleReloadAll(req);
        return;
      }

      // 动态路由：/api/plugins/:id 及 /api/plugins/:id/:action
      final match = _pluginIdPattern.firstMatch(path);
      if (match != null) {
        final pluginId = match.group(1)!;
        final action = match.group(2); // null 或 "reload" 等

        if (action == null) {
          // /api/plugins/:id
          if (req.method == 'GET') {
            await _handleGetPlugin(req, pluginId);
            return;
          }
          if (req.method == 'DELETE') {
            await _handleUninstallPlugin(req, pluginId);
            return;
          }
        } else if (action == 'reload' && req.method == 'POST') {
          await _handleReloadPlugin(req, pluginId);
          return;
        }
      }

      // 未匹配的路由
      await _writeError(req.response, HttpStatus.notFound, 'ERROR_NOT_FOUND',
          'Endpoint not found: ${req.method} $path');
    } catch (e, stackTrace) {
      debugPrint('PluginApiServer unhandled error: $e');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await _writeError(req.response, HttpStatus.internalServerError,
            'ERROR_INTERNAL', e.toString());
      } catch (_) {
        // 响应可能已被关闭
      }
    }
  }

  // ─── 端点实现 ──────────────────────────────────────────

  /// GET /api/health
  Future<void> _handleHealth(HttpRequest req) async {
    await _writeJson(req.response, HttpStatus.ok, {
      'ok': true,
      'data': {
        'app': 'RainCurtain',
        'appVersion': kAppVersion,
        'apiVersion': kApiVersion,
        'sandboxServerPort': sandboxServerPort,
      },
    });
  }

  /// GET /api/plugins?manifestId=xxx
  Future<void> _handleListPlugins(HttpRequest req) async {
    final manifestId = req.uri.queryParameters['manifestId'];

    var list = pluginManager.plugins;
    if (manifestId != null && manifestId.isNotEmpty) {
      list = list.where((p) => p.manifest.id == manifestId).toList();
    }

    await _writeJson(req.response, HttpStatus.ok, {
      'ok': true,
      'data': {
        'plugins': list.map(_pluginToJson).toList(),
      },
    });
  }

  /// GET /api/plugins/:id
  Future<void> _handleGetPlugin(HttpRequest req, String id) async {
    final plugin = pluginManager.getPluginById(id);
    if (plugin == null) {
      await _writeError(req.response, HttpStatus.notFound, 'ERROR_PLUGIN_NOT_FOUND',
          'Plugin not found: $id');
      return;
    }

    await _writeJson(req.response, HttpStatus.ok, {
      'ok': true,
      'data': _pluginToJson(plugin),
    });
  }

  /// POST /api/plugins/register
  Future<void> _handleRegisterPlugin(HttpRequest req) async {
    final body = await _readJsonBody(req);
    if (body == null) return; // 已写入错误响应

    final pluginId = body['pluginId'] as String?;
    final entryPath = body['entryPath'] as String?;
    final overwrite = body['overwrite'] as bool? ?? false;

    if (pluginId == null || pluginId.isEmpty) {
      _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
          'Missing required field: pluginId');
      return;
    }
    if (entryPath == null || entryPath.isEmpty) {
      _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
          'Missing required field: entryPath');
      return;
    }

    try {
      final plugin = await pluginManager.registerExistingPlugin(
        pluginId: pluginId,
        entryPath: entryPath,
        overwrite: overwrite,
      );
      await _writeJson(req.response, HttpStatus.ok, {
        'ok': true,
        'data': _pluginToJson(plugin),
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('插件已存在')) {
        await _writeError(req.response, HttpStatus.conflict, 'ERROR_PLUGIN_EXISTS',
            msg);
      } else if (msg.contains('不存在')) {
        await _writeError(req.response, HttpStatus.notFound, 'ERROR_FILE_NOT_FOUND',
            msg);
      } else if (msg.contains('manifest') || msg.contains('格式')) {
        await _writeError(req.response, HttpStatus.badRequest,
            'ERROR_INVALID_MANIFEST', msg);
      } else {
        await _writeError(
            req.response, HttpStatus.internalServerError, 'ERROR_INTERNAL', msg);
      }
    }
  }

  /// POST /api/plugins/install
  Future<void> _handleInstallPlugin(HttpRequest req) async {
    final body = await _readJsonBody(req);
    if (body == null) return;

    final zipPath = body['zipPath'] as String?;
    final overwrite = body['overwrite'] as bool? ?? false;

    if (zipPath == null || zipPath.isEmpty) {
      _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
          'Missing required field: zipPath');
      return;
    }

    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      _writeError(req.response, HttpStatus.notFound, 'ERROR_FILE_NOT_FOUND',
          'Zip file not found: $zipPath');
      return;
    }

    try {
      final plugin = await pluginManager.installPluginFromZip(
        zipFile,
        overwrite: overwrite,
      );
      await _writeJson(req.response, HttpStatus.ok, {
        'ok': true,
        'data': _pluginToJson(plugin),
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('插件已存在')) {
        await _writeError(req.response, HttpStatus.conflict, 'ERROR_PLUGIN_EXISTS',
            msg);
      } else if (msg.contains('manifest') || msg.contains('格式')) {
        await _writeError(req.response, HttpStatus.badRequest,
            'ERROR_INVALID_MANIFEST', msg);
      } else {
        await _writeError(
            req.response, HttpStatus.internalServerError, 'ERROR_INTERNAL', msg);
      }
    }
  }

  /// DELETE /api/plugins/:id
  Future<void> _handleUninstallPlugin(HttpRequest req, String id) async {
    final plugin = pluginManager.getPluginById(id);
    if (plugin == null) {
      await _writeError(req.response, HttpStatus.notFound, 'ERROR_PLUGIN_NOT_FOUND',
          'Plugin not found: $id');
      return;
    }

    try {
      await pluginManager.uninstallPlugin(id);
      await _writeJson(req.response, HttpStatus.ok, {
        'ok': true,
        'data': {'pluginId': id, 'deleted': true},
      });
    } on Exception catch (e) {
      await _writeError(req.response, HttpStatus.internalServerError,
          'ERROR_INTERNAL', e.toString());
    }
  }

  /// POST /api/plugins/:id/reload
  Future<void> _handleReloadPlugin(HttpRequest req, String id) async {
    try {
      final plugin = await pluginManager.reloadPlugin(id);
      if (plugin == null) {
        await _writeError(req.response, HttpStatus.notFound,
            'ERROR_PLUGIN_NOT_FOUND', 'Plugin not found: $id');
        return;
      }
      await _writeJson(req.response, HttpStatus.ok, {
        'ok': true,
        'data': _pluginToJson(plugin),
      });
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('manifest') || msg.contains('不存在')) {
        await _writeError(req.response, HttpStatus.badRequest,
            'ERROR_INVALID_MANIFEST', msg);
      } else {
        await _writeError(
            req.response, HttpStatus.internalServerError, 'ERROR_INTERNAL', msg);
      }
    }
  }

  /// POST /api/plugins/reload-all
  Future<void> _handleReloadAll(HttpRequest req) async {
    try {
      await pluginManager.reloadPlugins();
      await _writeJson(req.response, HttpStatus.ok, {
        'ok': true,
        'data': {'pluginCount': pluginManager.plugins.length},
      });
    } on Exception catch (e) {
      await _writeError(req.response, HttpStatus.internalServerError,
          'ERROR_INTERNAL', e.toString());
    }
  }

  // ─── 工具方法 ──────────────────────────────────────────

  /// 将 [LocalPlugin] 转换为 JSON Map
  Map<String, dynamic> _pluginToJson(LocalPlugin plugin) => {
        'id': plugin.id,
        'name': plugin.name,
        'description': plugin.description,
        'version': plugin.version,
        'author': plugin.author,
        'entryPath': plugin.entryPath,
        'sortOrder': pluginManager.plugins.indexOf(plugin),
      };

  /// 设置 CORS 响应头
  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
        'Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers',
        'Content-Type, Authorization, X-Requested-With');
  }

  /// 写入 JSON 响应
  Future<void> _writeJson(
      HttpResponse response, int status, Map<String, dynamic> body) async {
    _setCorsHeaders(response);
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  /// 写入错误响应
  Future<void> _writeError(
      HttpResponse response, int status, String code, String message) {
    return _writeJson(response, status, {
      'ok': false,
      'error': code,
      'message': message,
    });
  }

  /// 读取并解析请求体中的 JSON。
  ///
  /// 解析失败时自动写入 400 错误响应并返回 null。
  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest req) async {
    try {
      final bodyStr = await utf8.decoder.bind(req).join();
      if (bodyStr.isEmpty) {
        _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
            'Empty request body');
        return null;
      }
      final decoded = jsonDecode(bodyStr);
      if (decoded is! Map<String, dynamic>) {
        _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
            'Request body must be a JSON object');
        return null;
      }
      return decoded;
    } catch (e) {
      _writeError(req.response, HttpStatus.badRequest, 'ERROR_BAD_REQUEST',
          'Invalid JSON: $e');
      return null;
    }
  }
}
