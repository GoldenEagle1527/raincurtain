import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SandboxServer {
  final Directory documentRoot;
  final int port;
  HttpServer? _server;
  final Map<String, Database> _dbCache = {};

  SandboxServer({required this.documentRoot, this.port = 0});

  /// 服务器实际监听的端口（start() 成功后可用）
  int get actualPort => _server?.port ?? 0;

  Future<Database> _getDatabase(String pluginId, String rcpluginPath) async {
    if (_dbCache.containsKey(pluginId)) {
      return _dbCache[pluginId]!;
    }
    final db = await databaseFactory.openDatabase(
      rcpluginPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    _dbCache[pluginId] = db;
    return db;
  }

  Future<int> start() async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );
    _server!.listen(
      (HttpRequest request) async {
        final path = request.uri.path == '/' ? '/index.html' : request.uri.path;

        // 处理 OPTIONS 预检请求
        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.noContent;
          _setCorsHeaders(request.response);
          await request.response.close();
          return;
        }

        // 检查是否为字体文件请求
        if (path.startsWith('/__raincurtain_fonts__/')) {
          await _serveFontFile(request, path);
          return;
        }

        // 统一提取 pluginId 和内部路径
        final cleanPath = path == '/' ? '/index.html' : path;
        final parts = cleanPath.substring(1).split('/');
        if (parts.isEmpty || parts[0].isEmpty) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('Not Found');
          await request.response.close();
          return;
        }

        var pluginId = parts[0];
        if (pluginId.endsWith('.rcplugin')) {
          pluginId = pluginId.substring(0, pluginId.length - '.rcplugin'.length);
        }
        var filePath = parts.sublist(1).join('/');
        if (filePath.isEmpty) {
          filePath = 'index.html';
        }

        final pluginDir = Directory(p.join(documentRoot.path, pluginId));
        if (await pluginDir.exists()) {
          // 开发模式：直接读取文件
          final file = File(p.join(documentRoot.path, path.substring(1)));

          // 路径遍历防御：规范化后校验是否仍在沙箱根目录内
          final canonicalRoot = p.canonicalize(documentRoot.path);
          final canonicalFile = p.canonicalize(file.path);
          if (!p.isWithin(canonicalRoot, canonicalFile) &&
              canonicalFile != canonicalRoot) {
            request.response.statusCode = HttpStatus.forbidden;
            request.response.write('Forbidden');
            await request.response.close();
            return;
          }

          if (await file.exists()) {
            final ext = p.extension(file.path).toLowerCase();
            final contentType = _getContentType(ext);

            request.response.headers.contentType = ContentType.parse(contentType);
            // 使用 set 而非 add，防止 Dart HttpServer 自动添加后再追加造成重复
            _setCorsHeaders(request.response);

            await request.response.addStream(file.openRead());
            await request.response.close();
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Not Found');
            await request.response.close();
          }
        } else {
          // 发布模式：尝试加载 rcplugin 数据库文件
          final rcpluginFile = File(p.join(documentRoot.path, '$pluginId.rcplugin'));
          if (await rcpluginFile.exists()) {
            // 路径防越界校验
            final cleanFilePath = p.normalize(filePath).replaceAll('\\', '/');
            if (cleanFilePath.startsWith('../') || cleanFilePath == '..') {
              request.response.statusCode = HttpStatus.forbidden;
              request.response.write('Forbidden');
              await request.response.close();
              return;
            }

            try {
              final db = await _getDatabase(pluginId, rcpluginFile.path);
              final results = await db.query(
                'sqlar',
                columns: ['sz', 'data'],
                where: 'name = ?',
                whereArgs: [cleanFilePath],
              );

              if (results.isNotEmpty) {
                final row = results.first;
                final sz = row['sz'] as int;
                final data = row['data'] as Uint8List;

                Uint8List contentBytes;
                if (sz > data.length) {
                  // deflateRaw 压缩，解密还原
                  contentBytes = Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
                } else {
                  contentBytes = data;
                }

                final ext = p.extension(cleanFilePath).toLowerCase();
                final contentType = _getContentType(ext);

                request.response.headers.contentType = ContentType.parse(contentType);
                _setCorsHeaders(request.response);
                request.response.add(contentBytes);
                await request.response.close();
              } else {
                request.response.statusCode = HttpStatus.notFound;
                request.response.write('Not Found in SQLite Archive');
                await request.response.close();
              }
            } catch (e) {
              debugPrint('[SandboxServer] Error reading sqlite archive: $e');
              request.response.statusCode = HttpStatus.internalServerError;
              request.response.write('Internal Server Error: $e');
              await request.response.close();
            }
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('Not Found');
            await request.response.close();
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // 单个请求流错误仅打印日志，不中断服务器
        debugPrint('[SandboxServer] Stream error: $error');
      },
      cancelOnError: false,
    );
    return _server!.port;
  }

  /// 统一设置 CORS 响应头（使用 set 避免重复）
  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
  }

  /// 服务字体文件 (从 Flutter assets 加载)
  Future<void> _serveFontFile(HttpRequest request, String path) async {
    try {
      final fontName = path.substring('/__raincurtain_fonts__/'.length);

      String assetPath;
      if (fontName.startsWith('MaterialIcons')) {
        assetPath = 'assets/fonts/material-icons/$fontName';
      } else {
        assetPath = 'assets/fonts/$fontName';
      }

      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      final ext = p.extension(fontName).toLowerCase();
      final contentType = _getContentType(ext);

      request.response.headers.contentType = ContentType.parse(contentType);
      _setCorsHeaders(request.response);
      request.response.headers.set('Cache-Control', 'public, max-age=31536000');

      request.response.add(bytes);
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Font Not Found: $e');
      await request.response.close();
    }
  }

  /// 获取文件的 Content-Type
  String _getContentType(String ext) {
    return switch (ext) {
      '.html' => 'text/html',
      '.js' => 'text/javascript',
      '.css' => 'text/css',
      '.wasm' => 'application/wasm',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.svg' => 'image/svg+xml',
      '.json' => 'application/json',
      '.ttf' => 'font/ttf',
      '.otf' => 'font/otf',
      '.woff' => 'font/woff',
      '.woff2' => 'font/woff2',
      _ => 'application/octet-stream',
    };
  }

  /// 关闭并释放特定插件的 SQLite 数据库连接缓存，防止 Windows 文件独占锁
  Future<void> releaseDatabaseCache(String pluginId) async {
    final db = _dbCache.remove(pluginId);
    if (db != null) {
      try {
        await db.close();
        debugPrint('[SandboxServer] Released database connection cache for $pluginId');
      } catch (e) {
        debugPrint('[SandboxServer] Error closing cached db for $pluginId: $e');
      }
    }
  }

  Future<void> close() async {
    await _server?.close();
    for (final db in _dbCache.values) {
      try {
        await db.close();
      } catch (e) {
        debugPrint('[SandboxServer] Error closing cached db: $e');
      }
    }
    _dbCache.clear();
  }
}
