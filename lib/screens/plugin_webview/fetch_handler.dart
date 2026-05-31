import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:path_provider/path_provider.dart';
import '../../main.dart' show sandboxServerPort;
import '../../utils/permission_utils.dart';
import 'fetch_cache.dart';

/// Fetch/XHR 网络请求相关的 JS polyfill 和 Handler 注册
mixin FetchMixin {
  // 网络请求管理：支持请求取消
  final Map<String, http.Client> _activeRequests = {};

  // 性能监控：记录请求指标
  final Map<String, FetchMetrics> _requestMetrics = {};

  // GET 请求缓存（LRU，最多 50 条，按 Cache-Control 设置 TTL）
  final RequestCache _requestCache = RequestCache();

  /// 注入 JS：拦截跨域 fetch/XMLHttpRequest，请求改由 Flutter 侧发起
  static String get polyfillJS => r"""
(function() {
  if (window.__raincurtainFetchPatched) return;
  window.__raincurtainFetchPatched = true;

  var originalFetch = window.fetch ? window.fetch.bind(window) : null;
  var OriginalXHR = window.XMLHttpRequest;
  var localhostOrigin = 'http://localhost:""" '$sandboxServerPort' r"""';

  // 生成唯一请求 ID (简化版 UUID v4)
  function generateRequestId() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0;
      var v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  function isLocalRequest(url) {
    if (!url) return true;
    if (url.indexOf('data:') === 0 || url.indexOf('blob:') === 0) return true;
    if (url.indexOf('/') === 0) return true;
    if (url.indexOf(localhostOrigin) === 0) return true;
    try {
      var resolved = new URL(url, window.location.href);
      return resolved.origin === window.location.origin;
    } catch (_) {
      return true;
    }
  }

  function headersToObject(headers) {
    var result = {};
    if (!headers) return result;

    if (typeof Headers !== 'undefined' && headers instanceof Headers) {
      headers.forEach(function(value, key) {
        result[key] = value;
      });
      return result;
    }

    if (Array.isArray(headers)) {
      headers.forEach(function(entry) {
        if (Array.isArray(entry) && entry.length >= 2) {
          result[String(entry[0])] = String(entry[1]);
        }
      });
      return result;
    }

    Object.keys(headers).forEach(function(key) {
      result[key] = String(headers[key]);
    });
    return result;
  }

  // 将 File/Blob 转为 base64 字符串（不含 data-URL 前缀）
  function blobToBase64(blob) {
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onloadend = function() {
        var result = reader.result || '';
        var commaIndex = result.indexOf(',');
        resolve(commaIndex >= 0 ? result.substring(commaIndex + 1) : '');
      };
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  function arrayBufferToBase64(buffer) {
    var bytes = new Uint8Array(buffer);
    var binary = '';
    var chunkSize = 0x8000;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      var chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, chunk);
    }
    return btoa(binary);
  }

  function base64ToUint8Array(base64) {
    var binary = atob(base64 || '');
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  // 规范化请求体：支持 File/Blob 作为 multipart 字段
  async function normalizeBody(body) {
    if (body == null) return null;
    if (typeof body === 'string') {
      // 大字符串或含 data: URI 的字符串以 base64 传输，
      // 避免 callHandler 序列化时触发 WebView bridge 限制
      if (body.length > 32768 || body.indexOf('data:') >= 0) {
        try {
          var encoded = btoa(unescape(encodeURIComponent(body)));
          return { kind: 'base64-text', data: encoded };
        } catch (_) {
          // btoa 失败时回退为 TextEncoder + 手动 base64
          try {
            var bytes = new TextEncoder().encode(body);
            var binary = '';
            var chunkSize = 0x8000;
            for (var offset = 0; offset < bytes.length; offset += chunkSize) {
              binary += String.fromCharCode.apply(null, bytes.subarray(offset, offset + chunkSize));
            }
            return { kind: 'base64-text', data: btoa(binary) };
          } catch (_2) {
            return { kind: 'text', data: body };
          }
        }
      }
      return { kind: 'text', data: body };
    }
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      return { kind: 'text', data: body.toString() };
    }
    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      var entries = [];
      var filePromises = [];
      body.forEach(function(value, key) {
        if (typeof File !== 'undefined' && value instanceof File) {
          var idx = entries.length;
          entries.push({ key: key, type: 'file', filename: value.name, contentType: value.type || 'application/octet-stream', data: null });
          filePromises.push(
            blobToBase64(value).then(function(b64) { entries[idx].data = b64; })
          );
        } else if (typeof Blob !== 'undefined' && value instanceof Blob) {
          var idx2 = entries.length;
          entries.push({ key: key, type: 'file', filename: 'blob', contentType: value.type || 'application/octet-stream', data: null });
          filePromises.push(
            blobToBase64(value).then(function(b64) { entries[idx2].data = b64; })
          );
        } else {
          entries.push({ key: key, type: 'text', data: String(value) });
        }
      });
      if (filePromises.length > 0) {
        await Promise.all(filePromises);
      }
      return { kind: 'form-data', data: JSON.stringify(entries) };
    }
    if (typeof Blob !== 'undefined' && body instanceof Blob) {
      return { kind: 'base64', data: await blobToBase64(body) };
    }
    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
      return { kind: 'base64', data: arrayBufferToBase64(body) };
    }
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(body)) {
      return {
        kind: 'base64',
        data: arrayBufferToBase64(body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)),
      };
    }
    return { kind: 'text', data: String(body) };
  }

  function buildResponse(result, url) {
    var headers = new Headers(result.headers || {});
    var body = result.bodyBase64 != null
      ? base64ToUint8Array(result.bodyBase64)
      : (result.bodyText || '');
    var response = new Response(body, {
      status: result.status,
      statusText: result.statusText || '',
      headers: headers,
    });
    try {
      Object.defineProperty(response, 'url', {
        value: url,
        configurable: true,
      });
    } catch (_) {}
    return response;
  }

  // 构建一个流式 Response，Flutter 通过 window.__rc_stream_<id> 推送数据块
  function buildStreamingResponse(meta, url, requestId) {
    var responseHeaders = new Headers(meta.headers || {});
    var streamController;
    var stream = new ReadableStream({
      start: function(controller) {
        streamController = controller;
        // 注册全局回调，Flutter 通过 evaluateJavascript 调用
        window['__rc_stream_chunk_' + requestId] = function(base64Chunk) {
          try {
            controller.enqueue(base64ToUint8Array(base64Chunk));
          } catch (_) {}
        };
        window['__rc_stream_done_' + requestId] = function() {
          try { controller.close(); } catch (_) {}
          delete window['__rc_stream_chunk_' + requestId];
          delete window['__rc_stream_done_' + requestId];
          delete window['__rc_stream_error_' + requestId];
        };
        window['__rc_stream_error_' + requestId] = function(msg) {
          try { controller.error(new TypeError(msg)); } catch (_) {}
          delete window['__rc_stream_chunk_' + requestId];
          delete window['__rc_stream_done_' + requestId];
          delete window['__rc_stream_error_' + requestId];
        };
      },
      cancel: function() {
        // User cancelled the reader — abort the Flutter-side request
        window.flutter_inappwebview && window.flutter_inappwebview.callHandler('raincurtain_abort', { requestId: requestId }).catch(function(){});
        delete window['__rc_stream_chunk_' + requestId];
        delete window['__rc_stream_done_' + requestId];
        delete window['__rc_stream_error_' + requestId];
      },
    });

    var response = new Response(stream, {
      status: meta.status,
      statusText: meta.statusText || '',
      headers: responseHeaders,
    });
    try {
      Object.defineProperty(response, 'url', { value: url, configurable: true });
    } catch (_) {}
    return response;
  }

  async function interceptedFetch(resource, init) {
    var request = resource instanceof Request ? resource : null;
    var url = request ? request.url : String(resource);

    if (isLocalRequest(url) || !window.flutter_inappwebview) {
      if (!originalFetch) {
        throw new Error('Native fetch is unavailable');
      }
      return originalFetch(resource, init);
    }

    var method = 'GET';
    var headers = {};
    var body = null;
    var signal = null;

    if (request) {
      method = request.method || method;
      headers = headersToObject(request.headers);
      signal = request.signal;
      if (!init || init.body === undefined) {
        body = await normalizeBody(await request.clone().arrayBuffer());
      }
    }

    if (init) {
      if (init.method) method = init.method;
      if (init.headers) headers = headersToObject(init.headers);
      if (init.body !== undefined) body = await normalizeBody(init.body);
      if (init.signal) signal = init.signal;
    }

    // 生成请求 ID 用于取消
    var requestId = generateRequestId();

    // 如果有 AbortSignal，监听取消事件
    if (signal) {
      if (signal.aborted) {
        throw new DOMException('The operation was aborted.', 'AbortError');
      }
      signal.addEventListener('abort', function() {
        window.flutter_inappwebview.callHandler('raincurtain_abort', {
          requestId: requestId,
        }).catch(function(e) {
          console.warn('Failed to abort request:', e);
        });
      });
    }

    // 判断是否请求流式响应：Accept 含 text/event-stream 或显式 rc-stream 头
    var wantsStream = (headers['accept'] || headers['Accept'] || '').indexOf('text/event-stream') >= 0
      || headers['x-rc-stream'] === '1';

    var result;
    try {
      result = await window.flutter_inappwebview.callHandler('raincurtain_fetch', {
        requestId: requestId,
        url: url,
        method: method,
        headers: headers,
        body: body,
        stream: wantsStream,
      });
    } catch (handlerErr) {
      console.error('[interceptedFetch] callHandler threw:', handlerErr);
      throw new TypeError('callHandler failed: ' + (handlerErr && handlerErr.message ? handlerErr.message : String(handlerErr)));
    }

    if (!result) {
      console.error('[interceptedFetch] Flutter returned null/undefined');
      throw new TypeError('Network request failed: no response from host');
    }
    // success 字段表示网络层是否成功（有 HTTP 响应即为 true，包括 4xx/5xx）
    // 仅当网络层失败（DNS/超时/连接拒绝等）时才抛 TypeError
    // 兼容旧版：若没有 success 字段，回退到用 ok 判断
    var netSuccess = (typeof result.success === 'boolean') ? result.success : (result.ok === true);
    if (!netSuccess) {
      console.error('[interceptedFetch] Network-level failure:', result);
      throw new TypeError(result.error || 'Network request failed');
    }

    // 如果 Flutter 确认以流式方式响应
    if (result.streaming) {
      return buildStreamingResponse(result, url, requestId);
    }

    return buildResponse(result, url);
  }

  if (originalFetch) {
    window.fetch = function(resource, init) {
      return interceptedFetch(resource, init);
    };
  }

  if (OriginalXHR) {
    function RainCurtainXHR() {
      this._nativeXhr = new OriginalXHR();
      this._method = 'GET';
      this._url = '';
      this._async = true;
      this._headers = {};
      this._body = null;
      this._intercept = false;
      this._responseHeaders = {};
      this.readyState = 0;
      this.status = 0;
      this.statusText = '';
      this.response = null;
      this.responseText = '';
      this.responseType = '';
      this.timeout = 0;
      this.withCredentials = false;
      this.onreadystatechange = null;
      this.onload = null;
      this.onerror = null;
      this.onabort = null;
      this.ontimeout = null;
      this.onloadend = null;
      this.onprogress = null;
      this._bindNativeEvents();
    }

    RainCurtainXHR.UNSENT = 0;
    RainCurtainXHR.OPENED = 1;
    RainCurtainXHR.HEADERS_RECEIVED = 2;
    RainCurtainXHR.LOADING = 3;
    RainCurtainXHR.DONE = 4;

    RainCurtainXHR.prototype._bindNativeEvents = function() {
      var self = this;
      var nativeXhr = this._nativeXhr;
      nativeXhr.onreadystatechange = function() {
        if (self._intercept) return;
        self.readyState = nativeXhr.readyState;
        if (nativeXhr.readyState >= 2) {
          self.status = nativeXhr.status;
          self.statusText = nativeXhr.statusText;
        }
        if (nativeXhr.readyState === 4) {
          self.response = nativeXhr.response;
          self.responseText = nativeXhr.responseText;
        }
        self._emit('readystatechange');
      };
      nativeXhr.onload = function(event) {
        if (self._intercept) return;
        self._emit('load', event);
        self._emit('loadend', event);
      };
      nativeXhr.onerror = function(event) {
        if (self._intercept) return;
        self._emit('error', event);
        self._emit('loadend', event);
      };
      nativeXhr.onabort = function(event) {
        if (self._intercept) return;
        self._emit('abort', event);
        self._emit('loadend', event);
      };
      nativeXhr.ontimeout = function(event) {
        if (self._intercept) return;
        self._emit('timeout', event);
        self._emit('loadend', event);
      };
      nativeXhr.onprogress = function(event) {
        if (self._intercept) return;
        self._emit('progress', event);
      };
    };

    RainCurtainXHR.prototype._emit = function(type, event) {
      var handler = this['on' + type];
      if (typeof handler === 'function') {
        handler.call(this, event);
      }
    };

    RainCurtainXHR.prototype.open = function(method, url, async, user, password) {
      this._method = method || 'GET';
      this._url = String(url);
      this._async = async !== false;
      this._intercept = !isLocalRequest(this._url) && !!window.flutter_inappwebview;
      this.readyState = 1;
      this._emit('readystatechange');
      if (!this._intercept) {
        this._nativeXhr.open(method, url, async, user, password);
      }
    };

    RainCurtainXHR.prototype.setRequestHeader = function(name, value) {
      this._headers[name] = String(value);
      if (!this._intercept) {
        this._nativeXhr.setRequestHeader(name, value);
      }
    };

    RainCurtainXHR.prototype.getAllResponseHeaders = function() {
      if (!this._intercept) {
        return this._nativeXhr.getAllResponseHeaders();
      }
      return Object.keys(this._responseHeaders).map(function(key) {
        return key + ': ' + String(this._responseHeaders[key]);
      }, this).join('\r\n');
    };

    RainCurtainXHR.prototype.getResponseHeader = function(name) {
      if (!this._intercept) {
        return this._nativeXhr.getResponseHeader(name);
      }
      var lowerName = String(name).toLowerCase();
      var keys = Object.keys(this._responseHeaders);
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].toLowerCase() === lowerName) {
          return String(this._responseHeaders[keys[i]]);
        }
      }
      return null;
    };

    RainCurtainXHR.prototype.abort = function() {
      if (!this._intercept) {
        return this._nativeXhr.abort();
      }
      this.readyState = 4;
      this._emit('abort');
      this._emit('loadend');
    };

    RainCurtainXHR.prototype.overrideMimeType = function(mime) {
      if (!this._intercept && this._nativeXhr.overrideMimeType) {
        this._nativeXhr.overrideMimeType(mime);
      }
    };

    RainCurtainXHR.prototype.send = async function(body) {
      if (!this._intercept) {
        this._nativeXhr.responseType = this.responseType;
        this._nativeXhr.timeout = this.timeout;
        this._nativeXhr.withCredentials = this.withCredentials;
        return this._nativeXhr.send(body);
      }

      try {
        this._body = await normalizeBody(body);
        var result = await window.flutter_inappwebview.callHandler('raincurtain_fetch', {
          url: this._url,
          method: this._method,
          headers: this._headers,
          body: this._body,
          stream: false,
        });

        // success 表示网络层成功（有 HTTP 响应），HTTP 4xx/5xx 仍算成功
        var netSuccess = result && ((typeof result.success === 'boolean') ? result.success : (result.ok === true));
        if (!netSuccess) {
          throw new Error((result && result.error) || 'Network request failed');
        }

        this.status = result.status;
        this.statusText = result.statusText || '';
        this._responseHeaders = result.headers || {};
        this.readyState = 2;
        this._emit('readystatechange');
        this.readyState = 3;
        this._emit('readystatechange');

        if (this.responseType === 'arraybuffer' || this.responseType === 'blob') {
          var bytes = base64ToUint8Array(result.bodyBase64 || '');
          this.response = this.responseType === 'blob' ? new Blob([bytes]) : bytes.buffer;
          this.responseText = '';
        } else {
          this.responseText = result.bodyText || '';
          this.response = this.responseText;
        }

        this.readyState = 4;
        this._emit('readystatechange');
        this._emit('load');
        this._emit('loadend');
      } catch (error) {
        this.readyState = 4;
        this.status = 0;
        this.statusText = '';
        this.response = null;
        this.responseText = '';
        this._emit('readystatechange');
        this._emit('error', error);
        this._emit('loadend', error);
      }
    };

    Object.defineProperty(RainCurtainXHR.prototype, 'responseURL', {
      get: function() {
        return this._url;
      },
    });

    window.XMLHttpRequest = RainCurtainXHR;
  }
})();
""";

  /// 解析 MIME 类型字符串为 MediaType（仅用于 multipart 文件上传）
  http_parser.MediaType _parseMediaType(String contentType) {
    try {
      return http_parser.MediaType.parse(contentType);
    } catch (_) {
      return http_parser.MediaType('application', 'octet-stream');
    }
  }

  /// 处理 WebView 触发的下载请求
  /// 支持 data: URI（base64 内联数据）和普通 http/https URL
  Future<void> handleDownload({
    required BuildContext context,
    required bool mounted,
    required String url,
    String? suggestedFilename,
    String? mimeType,
  }) async {
    try {
      // 确定保存目录：优先使用外部存储 Downloads，回退到应用文档目录
      Directory saveDir;
      if (Platform.isAndroid) {
        // 按需请求存储权限（Android 13+ 自动处理，不会弹窗）
        final hasStorage = await PermissionUtils.requestStoragePermission();

        // Android 外部存储 Downloads 目录
        saveDir = Directory('/storage/emulated/0/Download');
        if (!hasStorage || !await saveDir.exists()) {
          // 权限未授予或目录不存在，回退到应用文档目录
          saveDir = await getApplicationDocumentsDirectory();
        }
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }

      final filename = suggestedFilename?.isNotEmpty == true
          ? suggestedFilename!
          : 'download_${DateTime.now().millisecondsSinceEpoch}';
      final savePath = '${saveDir.path}/$filename';

      if (url.startsWith('data:')) {
        // 处理 data: URI（如 data:text/plain;base64,... 或 data:text/plain;charset=utf-8,...）
        final commaIdx = url.indexOf(',');
        if (commaIdx == -1) return;
        final header = url.substring(5, commaIdx); // 去掉 "data:"
        final body = url.substring(commaIdx + 1);
        final isBase64 = header.contains(';base64');
        final bytes = isBase64
            ? base64Decode(body)
            : utf8.encode(Uri.decodeComponent(body));
        await File(savePath).writeAsBytes(bytes);
      } else {
        // 普通 HTTP/HTTPS URL：用 HttpClient 下载
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        final bytes = await consolidateHttpClientResponseBytes(response);
        await File(savePath).writeAsBytes(bytes);
        client.close();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u2705 已下载到: $savePath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u274c 下载失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
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
          // --- 检查 GET 请求缓存 ---
          if (method == 'GET') {
            final cached = _requestCache.get(url);
            if (cached != null) {
              metrics.complete(cached.statusCode, cached.bodyBytes.length);
              metrics.log();
              _requestMetrics.remove(requestId);
              _activeRequests.remove(requestId);

              final responseHeaders = cached.headers;
              return {
                'ok': cached.statusCode >= 200 && cached.statusCode < 300,
                'success': true, // 缓存命中也算成功
                'status': cached.statusCode,
                'statusText': cached.reasonPhrase ?? '',
                'headers': responseHeaders,
                'bodyBase64': base64Encode(cached.bodyBytes),
                'streaming': false,
              };
            }
          }

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
                wvc.evaluateJavascript(
                    source: 'if(window["__rc_stream_chunk_$requestId"]) window["__rc_stream_chunk_$requestId"]("$b64");');
              },
              onDone: () {
                final wvc = getWebViewController();
                if (isMounted() && wvc != null) {
                  wvc.evaluateJavascript(
                      source: 'if(window["__rc_stream_done_$requestId"]) window["__rc_stream_done_$requestId"]();');
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
                  wvc.evaluateJavascript(
                      source: 'if(window["__rc_stream_error_$requestId"]) window["__rc_stream_error_$requestId"]($safeError);');
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

          // 存入缓存（仅 GET）
          if (method == 'GET' && response.statusCode >= 200 && response.statusCode < 300) {
            final cacheEntry = CachedResponse.fromResponse(response);
            if (cacheEntry != null) {
              _requestCache.put(url, cacheEntry);
            }
          }

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
    _requestCache.clear();
  }
}
