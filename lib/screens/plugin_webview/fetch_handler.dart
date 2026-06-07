import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../main.dart' show sandboxServerPort;
import '../../utils/permission_utils.dart';
import 'webview_scripts.dart';

/// Fetch/XHR 网络请求相关的 JS polyfill 和 Handler 注册
mixin FetchMixin {
  // 网络请求管理：支持请求取消
  final Map<String, http.Client> _activeRequests = {};

  // 性能监控：记录请求指标
  final Map<String, FetchMetrics> _requestMetrics = {};

  /// 注入 JS：拦截跨域 fetch/XMLHttpRequest，请求改由 Flutter 侧发起
  static String get polyfillJS => WebViewScripts.fetchPolyfillJS(sandboxServerPort);

  /// 解析 MIME 类型字符串为 MediaType（仅用于 multipart 文件上传）
  http_parser.MediaType _parseMediaType(String contentType) {
    try {
      return http_parser.MediaType.parse(contentType);
    } catch (_) {
      return http_parser.MediaType('application', 'octet-stream');
    }
  }

  /// 处理 WebView 触发的下载请求
  /// 支持 data: URI（base64 内联数据）、blob: URI（WebView evaluateJavascript）和普通 http/https URL
  Future<void> handleDownload({
    required BuildContext context,
    required bool Function() isMounted,
    required String url,
    InAppWebViewController? controller,
    String? suggestedFilename,
    String? mimeType,
  }) async {
    try {
      final filename = suggestedFilename?.isNotEmpty == true
          ? suggestedFilename!
          : 'download_${DateTime.now().millisecondsSinceEpoch}';

      List<String>? allowedExtensions;
      final dotIdx = filename.lastIndexOf('.');
      if (dotIdx > 0 && dotIdx < filename.length - 1) {
        allowedExtensions = [filename.substring(dotIdx + 1)];
      }

      Uint8List? fileBytes;

      if (url.startsWith('data:')) {
        final commaIdx = url.indexOf(',');
        if (commaIdx == -1) throw Exception('无效的 Data URI');
        final header = url.substring(5, commaIdx);
        final body = url.substring(commaIdx + 1);
        final isBase64 = header.contains(';base64');
        fileBytes = isBase64
            ? base64Decode(body)
            : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
      } else if (url.startsWith('blob:')) {
        if (controller == null) {
          throw Exception('WebView 控制器不可用，无法解析 blob 资源');
        }

        final jsCode = """
          (async function() {
            try {
              var response = await fetch('$url');
              var blob = await response.blob();
              return await new Promise(function(resolve, reject) {
                var reader = new FileReader();
                reader.onloadend = function() { resolve(reader.result); };
                reader.onerror = reject;
                reader.readAsDataURL(blob);
              });
            } catch (e) {
              return 'error: ' + e.message;
            }
          })()
        """;

        final dynamic jsResult = await controller.evaluateJavascript(source: jsCode);
        if (jsResult == null) {
          throw Exception('无法从 WebView 读取 blob 资源（返回空值）');
        }
        final String resultStr = jsResult.toString();
        if (resultStr.startsWith('error:')) {
          throw Exception('读取 blob 资源失败: ${resultStr.substring(6)}');
        }

        final commaIdx = resultStr.indexOf(',');
        if (commaIdx == -1) throw Exception('无效的 Blob Base64 数据');
        final header = resultStr.substring(5, commaIdx);
        final body = resultStr.substring(commaIdx + 1);
        final isBase64 = header.contains(';base64');
        fileBytes = isBase64
            ? base64Decode(body)
            : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));
      }

      String? savedPath;

      if (Platform.isWindows) {
        // Windows 平台：拉起系统的保存文件对话框，如果是网络资源，直接流式下载到该路径
        savedPath = await FilePicker.saveFile(
          dialogTitle: '保存文件',
          fileName: filename,
          type: allowedExtensions != null ? FileType.custom : FileType.any,
          allowedExtensions: allowedExtensions,
        );

        if (savedPath == null) {
          return; // 用户取消保存
        }

        if (fileBytes != null) {
          await File(savedPath).writeAsBytes(fileBytes);
        } else {
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final file = File(savedPath);
            final parent = file.parent;
            if (!await parent.exists()) {
              await parent.create(recursive: true);
            }
            final raf = await file.open(mode: FileMode.write);
            await response.forEach((chunk) async {
              await raf.writeFrom(chunk);
            });
            await raf.close();
          } else {
            client.close();
            throw Exception('服务器返回错误代码: ${response.statusCode}');
          }
          client.close();
        }
      } else if (Platform.isAndroid) {
        // Android 平台：下载数据（如果是网络 URL，流式下载到临时文件，再读取 bytes）并调用 FilePicker 导出
        Uint8List bytesToSave;
        if (fileBytes != null) {
          bytesToSave = fileBytes;
        } else {
          await PermissionUtils.requestStoragePermission();

          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_download_${DateTime.now().millisecondsSinceEpoch}');
          
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final raf = await tempFile.open(mode: FileMode.write);
            await response.forEach((chunk) async {
              await raf.writeFrom(chunk);
            });
            await raf.close();
            client.close();
            bytesToSave = await tempFile.readAsBytes();
            await tempFile.delete();
          } else {
            client.close();
            if (await tempFile.exists()) await tempFile.delete();
            throw Exception('服务器返回错误代码: ${response.statusCode}');
          }
        }

        savedPath = await FilePicker.saveFile(
          dialogTitle: '保存文件',
          fileName: filename,
          bytes: bytesToSave,
          type: allowedExtensions != null ? FileType.custom : FileType.any,
          allowedExtensions: allowedExtensions,
        );

        if (savedPath == null) {
          return; // 用户取消保存
        }
      } else {
        // 其他平台降级处理
        final saveDir = await getApplicationDocumentsDirectory();
        savedPath = '${saveDir.path}/$filename';
        if (fileBytes != null) {
          await File(savedPath).writeAsBytes(fileBytes);
        } else {
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(url));
          final response = await request.close();
          final bytes = await consolidateHttpClientResponseBytes(response);
          await File(savedPath).writeAsBytes(bytes);
          client.close();
        }
      }

      if (isMounted()) {
        final displayPath = savedPath.split(Platform.pathSeparator).last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ 已成功保存: $displayPath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 保存失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// 注册 <a download> 下载拦截 Handler
  /// 接收来自 polyfill JS 的下载请求，调用 handleDownload 走 Flutter 原生保存对话框
  void registerDownloadHandler(
    InAppWebViewController controller, {
    required BuildContext context,
    required bool Function() isMounted,
  }) {
    controller.addJavaScriptHandler(
      handlerName: 'raincurtain_download',
      callback: (args) async {
        if (args.isEmpty) return null;
        final data = args[0] as Map<dynamic, dynamic>;
        final url = data['url'] as String? ?? '';
        final filename = data['filename'] as String? ?? '';
        if (url.isEmpty) return null;

        await handleDownload(
          context: context,
          isMounted: isMounted,
          url: url,
          controller: controller,
          suggestedFilename: filename.isNotEmpty ? filename : null,
        );
        return null;
      },
    );
  }

  /// 注册 Fetch/XHR Handler
  void registerFetchHandlers(
    InAppWebViewController controller, {
    required InAppWebViewController? Function() getWebViewController,
    required bool Function() isMounted,
  }) {
    // 注册 JS Handler：接收来自 WebView 的跨域网络请求，由 Flutter 侧发起
    controller.addJavaScriptHandler(
      handlerName: 'raincurtain_fetch',
      callback: (args) async {
        if (args.isEmpty) {
          return {
            'ok': false,
            'success': false,
            'error': 'Missing request payload',
          };
        }

        final data = args[0] as Map<dynamic, dynamic>;
        final String url = data['url'] as String? ?? '';
        final String method = (data['method'] as String? ?? 'GET').toUpperCase();
        final Map<String, String> headers =
            Map<String, String>.from(data['headers'] as Map? ?? {});
        final bodyData = data['body'];
        final bool wantsStream = data['stream'] == true;
        final String requestId = data['requestId'] as String? ?? 'unknown';

        // DEBUG: 记录收到的请求
        String bodyKindDbg = 'none';
        int bodyLenDbg = 0;
        if (bodyData is Map) {
          bodyKindDbg = bodyData['kind']?.toString() ?? 'unknown';
          final d = bodyData['data'];
          if (d is String) bodyLenDbg = d.length;
        }
        debugPrint('[raincurtain_fetch] received: method=$method url=$url bodyKind=$bodyKindDbg bodyLen=$bodyLenDbg reqId=$requestId');

        if (url.isEmpty) {
          return {
            'ok': false,
            'success': false,
            'error': 'Empty URL',
          };
        }

        // 创建请求指标并记录开始时间
        final metrics = FetchMetrics(url: url, method: method);
        _requestMetrics[requestId] = metrics;

        final client = http.Client();
        _activeRequests[requestId] = client;

        bool isStreaming = false;
        try {
          http.BaseRequest request;

          // 构造请求体
          if (bodyData != null && bodyData is Map && method != 'GET' && method != 'HEAD') {
            final kind = bodyData['kind'] as String?;
            final payload = bodyData['data'];

            if (kind == 'text' && payload != null) {
              final req = http.Request(method, Uri.parse(url));
              req.body = payload.toString();
              request = req;
            } else if (kind == 'base64-text' && payload is String) {
              // JS 侧将文本 body 编码为 base64 传输（避免 data: URI 触发 bridge 限制）
              final req = http.Request(method, Uri.parse(url));
              try {
                req.bodyBytes = base64Decode(payload);
              } catch (decodeErr) {
                debugPrint('[raincurtain_fetch] base64-text decode failed: $decodeErr, payloadLen=${payload.length}');
                rethrow;
              }
              request = req;
            } else if (kind == 'base64' && payload is String) {
              final req = http.Request(method, Uri.parse(url));
              req.bodyBytes = base64Decode(payload);
              request = req;
            } else if (kind == 'form-data' && payload is String) {
              final req = http.MultipartRequest(method, Uri.parse(url));
              final entries = jsonDecode(payload) as List;
              for (final entry in entries) {
                final key = entry['key'] as String;
                final type = entry['type'] as String;
                if (type == 'text') {
                  req.fields[key] = entry['data'] as String;
                } else if (type == 'file') {
                  final filename = entry['filename'] as String;
                  final contentType = entry['contentType'] as String;
                  final base64Data = entry['data'] as String?;
                  if (base64Data != null && base64Data.isNotEmpty) {
                    final bytes = base64Decode(base64Data);
                    req.files.add(
                      http.MultipartFile.fromBytes(
                        key,
                        bytes,
                        filename: filename,
                        contentType: _parseMediaType(contentType),
                      ),
                    );
                  }
                }
              }
              request = req;
            } else {
              request = http.Request(method, Uri.parse(url));
            }
          } else {
            request = http.Request(method, Uri.parse(url));
          }

          request.headers.addAll(headers);

          // --- 流式响应处理 ---
          if (wantsStream) {
            final streamedResponse = await client.send(request);
            metrics.complete(streamedResponse.statusCode, 0);

            // 如果成功获取了响应，立即返回 header 和 streaming: true 给 JS
            final responseHeaders = streamedResponse.headers;
            final result = {
              'ok': streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300,
              'success': true, // 流式响应成功建立
              'status': streamedResponse.statusCode,
              'statusText': streamedResponse.reasonPhrase ?? '',
              'headers': responseHeaders,
              'streaming': true,
            };

            // 在后台读取流并通过 evaluateJavascript 推送给 JS
            int totalBytes = 0;
            streamedResponse.stream.listen(
              (chunk) {
                final wvc = getWebViewController();
                if (!isMounted() || wvc == null) return;
                totalBytes += chunk.length;
                final b64 = base64Encode(chunk);
                wvc
                    .evaluateJavascript(
                      source:
                          'if(window["__rc_stream_chunk_$requestId"]) window["__rc_stream_chunk_$requestId"]("$b64");',
                    )
                    .catchError(
                      (e) => debugPrint('[RC Fetch] chunk push error: $e'),
                    );
              },
              onDone: () {
                final wvc = getWebViewController();
                if (isMounted() && wvc != null) {
                  wvc
                      .evaluateJavascript(
                        source:
                            'if(window["__rc_stream_done_$requestId"]) window["__rc_stream_done_$requestId"]();',
                      )
                      .catchError(
                        (e) => debugPrint('[RC Fetch] done push error: $e'),
                      );
                }
                metrics.responseSize = totalBytes;
                metrics.log();
                _requestMetrics.remove(requestId);
                _activeRequests.remove(requestId);
                client.close();
              },
              onError: (error) {
                final wvc = getWebViewController();
                if (isMounted() && wvc != null) {
                  final safeError = jsonEncode(error.toString());
                  wvc
                      .evaluateJavascript(
                        source:
                            'if(window["__rc_stream_error_$requestId"]) window["__rc_stream_error_$requestId"]($safeError);',
                      )
                      .catchError(
                        (e) => debugPrint('[RC Fetch] error push error: $e'),
                      );
                }
                metrics.fail(error.toString());
                metrics.log();
                _requestMetrics.remove(requestId);
                _activeRequests.remove(requestId);
                client.close();
              },
              cancelOnError: true,
            );

            isStreaming = true;
            return result;
          }

          // --- 非流式响应处理 ---
          final streamedResponse = await client.send(request);
          final response = await http.Response.fromStream(streamedResponse);

          metrics.complete(response.statusCode, response.bodyBytes.length);
          metrics.log();
          _requestMetrics.remove(requestId);

          final responseHeaders = response.headers;

          return {
            'ok': response.statusCode >= 200 && response.statusCode < 300,
            'success': true, // 网络层成功（有 HTTP 响应）
            'status': response.statusCode,
            'statusText': response.reasonPhrase ?? '',
            'headers': responseHeaders,
            'bodyBase64': base64Encode(response.bodyBytes),
            'streaming': false,
          };
        } catch (e, st) {
          // 请求失败或被取消（网络层失败）
          debugPrint('[raincurtain_fetch] error reqId=$requestId: $e\n$st');
          metrics.fail(e.toString());
          metrics.log();
          _requestMetrics.remove(requestId);
          return {
            'ok': false,
            'success': false, // 网络层失败
            'error': e.toString(),
          };
        } finally {
          if (!isStreaming) {
            _activeRequests.remove(requestId);
            client.close();
          }
        }
      },
    );

    // 注册 JS Handler：用于取消网络请求
    controller.addJavaScriptHandler(
      handlerName: 'raincurtain_abort',
      callback: (args) async {
        if (args.isEmpty) return null;
        final data = args[0] as Map<dynamic, dynamic>;
        final requestId = data['requestId'] as String?;
        if (requestId != null && _activeRequests.containsKey(requestId)) {
          _activeRequests[requestId]?.close();
          _activeRequests.remove(requestId);

          final metrics = _requestMetrics[requestId];
          if (metrics != null) {
            metrics.fail('Aborted by client');
            metrics.log();
            _requestMetrics.remove(requestId);
          }
        }
        return null;
      },
    );
  }

  /// 释放所有活跃的 HTTP 请求
  void disposeFetch() {
    for (final client in _activeRequests.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _activeRequests.clear();
    _requestMetrics.clear();
  }
}

/// 网络请求性能指标
class FetchMetrics {
  final DateTime startTime;
  final String url;
  final String method;
  int? statusCode;
  int? responseSize;
  String? error;

  FetchMetrics({
    required this.url,
    required this.method,
  }) : startTime = DateTime.now();

  Duration get duration => DateTime.now().difference(startTime);

  void complete(int status, int size) {
    statusCode = status;
    responseSize = size;
  }

  void fail(String err) {
    error = err;
  }

  void log() {
    if (error != null) {
      debugPrint('[RainCurtain Fetch] ❌ $method $url\n  Error: $error\n  Duration: ${duration.inMilliseconds}ms');
    } else {
      debugPrint('[RainCurtain Fetch] ✅ $method $url\n  Status: $statusCode\n  Size: ${responseSize ?? 0} bytes\n  Duration: ${duration.inMilliseconds}ms');
    }
  }
}
