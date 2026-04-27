import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class SandboxServer {
  final Directory documentRoot;
  final int port;
  HttpServer? _server;

  SandboxServer({required this.documentRoot, this.port = 8080});

  Future<void> start() async {
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

      // 检查是否为反向代理请求（解决远端 API CORS 头重复问题）
      if (path.startsWith('/__proxy__/')) {
        await _handleProxy(request, path);
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
  }

  /// 统一设置 CORS 响应头（使用 set 避免重复）
  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
  }

  /// 反向代理：将 /__proxy__/<encoded-url> 的请求转发到真实外部 API
  /// 目的：远端 API 返回重复的 Access-Control-Allow-Origin 头，浏览器会拒绝。
  /// 通过本地代理转发，可以过滤掉问题头，注入干净的 CORS 头后返回给浏览器。
  /// 支持流式响应（SSE / streaming JSON），使用管道而非缓冲。
  Future<void> _handleProxy(HttpRequest request, String path) async {
    try {
      // 从路径中解析目标 URL，格式: /__proxy__/<URL编码后的完整URL>
      final encodedTarget = path.substring('/__proxy__/'.length);
      final targetUrl = Uri.parse(Uri.decodeComponent(encodedTarget));

      // 读取请求体
      final bodyBytes = await request.fold<List<int>>(
        [],
        (prev, chunk) => [...prev, ...chunk],
      );

      // 构建转发请求，保留原始请求头（排除 Host）
      final proxyRequest = http.Request(request.method, targetUrl);
      request.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'host' && lower != 'origin' && lower != 'referer') {
          proxyRequest.headers[name] = values.join(', ');
        }
      });
      if (bodyBytes.isNotEmpty) {
        proxyRequest.bodyBytes = bodyBytes;
      }

      // 发送请求到真实 API（使用 StreamedResponse 支持流式传输）
      final streamedResponse = await proxyRequest.send();

      // 设置状态码
      request.response.statusCode = streamedResponse.statusCode;

      // 转发响应头，但跳过远端错误的 CORS 头（稍后注入干净的）
      final skipHeaders = {
        'access-control-allow-origin',
        'access-control-allow-methods',
        'access-control-allow-headers',
        'access-control-allow-credentials',
        'transfer-encoding', // chunked 编码由 Dart 自动处理
      };
      streamedResponse.headers.forEach((name, value) {
        if (!skipHeaders.contains(name.toLowerCase())) {
          request.response.headers.set(name, value);
        }
      });

      // 注入干净的 CORS 头
      _setCorsHeaders(request.response);

      // 流式管道：直接将远端响应流接入本地响应，不在内存中缓冲整个响应体
      // 这使得 SSE / streaming JSON / 大文件下载均可正常工作
      await request.response.addStream(streamedResponse.stream);
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.set('Content-Type', 'application/json');
      _setCorsHeaders(request.response);
      request.response.write(jsonEncode({'error': 'Proxy error: $e'}));
      await request.response.close();
    }
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
