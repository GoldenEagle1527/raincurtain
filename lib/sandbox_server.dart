import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

class SandboxServer {
  final Directory documentRoot;
  final int port;
  HttpServer? _server;

  SandboxServer({required this.documentRoot, this.port = 0});

  /// 服务器实际监听的端口（start() 成功后可用）
  int get actualPort => _server?.port ?? 0;

  Future<int> start() async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: true,
    );
    _server!.listen((HttpRequest request) async {
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

      // 原有的文件服务逻辑
      final file = File(
        p.join(documentRoot.path, path.substring(1)),
      ); // substring(1) removes leading '/'

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
    });
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
      // 路径映射: /__raincurtain_fonts__/MaterialIcons-Regular.ttf
      // -> assets/fonts/material-icons/MaterialIcons-Regular.ttf
      // 或: /__raincurtain_fonts__/NotoSerifSC-VariableFont_wght.ttf
      // -> assets/fonts/NotoSerifSC-VariableFont_wght.ttf
      final fontName = path.substring('/__raincurtain_fonts__/'.length);
      
      // 判断是 Material Icons 还是其他字体
      String assetPath;
      if (fontName.startsWith('MaterialIcons')) {
        assetPath = 'assets/fonts/material-icons/$fontName';
      } else {
        assetPath = 'assets/fonts/$fontName';
      }

      // 从 assets 加载字体文件
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      // 设置正确的 Content-Type
      final ext = p.extension(fontName).toLowerCase();
      final contentType = _getContentType(ext);

      request.response.headers.contentType = ContentType.parse(contentType);
      // 使用 set 而非 add，防止重复
      _setCorsHeaders(request.response);
      // 缓存字体文件1年
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

  Future<void> close() async {
    await _server?.close();
  }
}
