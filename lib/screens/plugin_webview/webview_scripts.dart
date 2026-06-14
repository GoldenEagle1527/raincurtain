class WebViewScripts {
  static String fetchPolyfillJS(int sandboxServerPort) {
    return r"""
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
        if (this._async) {
          this._nativeXhr.responseType = this.responseType;
          this._nativeXhr.timeout = this.timeout;
          this._nativeXhr.withCredentials = this.withCredentials;
        }
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
    window.__raincurtainNativeXMLHttpRequest = OriginalXHR;
  }

  // ===== 拦截 <a download> 点击，转由 Flutter 处理 =====
  // 在 document 层面捕获所有点击，检测目标是否为带 download 属性的 <a> 标签
  document.addEventListener('click', async function(e) {
    if (!window.flutter_inappwebview) return;

    // 找到最近的 <a> 祖先
    var el = e.target;
    while (el && el.tagName !== 'A') {
      el = el.parentElement;
    }
    if (!el || el.tagName !== 'A') return;

    // 必须带有 download 属性
    if (!el.hasAttribute('download')) return;

    var href = el.href || '';
    if (!href) return;

    // 阻止 WebView 原生下载行为（必须在 await 之前同步调用）
    e.preventDefault();
    e.stopPropagation();

    var filename = el.getAttribute('download') || '';
    if (!filename) {
      // 从 URL 推断文件名
      try {
        var pathname = new URL(href).pathname;
        filename = pathname.substring(pathname.lastIndexOf('/') + 1) || 'download';
      } catch (_) {
        filename = 'download';
      }
    }

    // 对于 blob: URL，立即在 JS 侧读取数据并转为 data: URI
    // 原因：插件代码可能在 a.click() 后立即 revokeObjectURL，
    // 若等到 Flutter 异步回调再去读取，blob 很可能已被释放
    if (href.indexOf('blob:') === 0) {
      try {
        var fetchFn = originalFetch || window.fetch;
        var resp = await fetchFn(href);
        var blob = await resp.blob();
        var mimeType = blob.type || 'application/octet-stream';
        var base64 = await blobToBase64(blob);
        href = 'data:' + mimeType + ';base64,' + base64;
      } catch (blobErr) {
        console.error('[raincurtain] failed to read blob before revoke:', blobErr);
        return;
      }
    }

    window.flutter_inappwebview.callHandler('raincurtain_download', {
      url: href,
      filename: filename,
    }).catch(function(err) {
      console.error('[raincurtain] download handler failed:', err);
    });
  }, true); // 使用捕获阶段确保在插件代码之前执行

})();
""";
  }

  static const String fileSystemPolyfillJS = r"""
(function() {
  if (window.__raincurtainFSPatched) return;
  window.__raincurtainFSPatched = true;

  // ===== 工具函数 =====

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

  async function blobToBase64(blob) {
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

  function callFlutter(handler, data) {
    if (!window.flutter_inappwebview) {
      return Promise.reject(new DOMException('Host bridge not available', 'AbortError'));
    }
    return window.flutter_inappwebview.callHandler(handler, data);
  }

  // 从 options.types 中提取扩展名列表
  function extractExtensions(types) {
    if (!types || !Array.isArray(types)) return null;
    var exts = [];
    for (var i = 0; i < types.length; i++) {
      var accept = types[i].accept;
      if (!accept) continue;
      var mimeKeys = Object.keys(accept);
      for (var j = 0; j < mimeKeys.length; j++) {
        var patterns = accept[mimeKeys[j]];
        if (Array.isArray(patterns)) {
          for (var k = 0; k < patterns.length; k++) {
            var ext = patterns[k];
            if (typeof ext === 'string') {
              exts.push(ext.replace(/^\./, ''));
            }
          }
        }
      }
    }
    return exts.length > 0 ? exts : null;
  }

  // ===== FileSystemHandle 基类 =====

  function FileSystemHandle(kind, name, path) {
    this.kind = kind;
    this.name = name;
    this._path = path;
  }

  FileSystemHandle.prototype.isSameEntry = function(other) {
    return Promise.resolve(
      other && other._path === this._path && other.kind === this.kind
    );
  };

  FileSystemHandle.prototype.queryPermission = function() {
    return Promise.resolve('granted');
  };

  FileSystemHandle.prototype.requestPermission = function() {
    return Promise.resolve('granted');
  };

  // ===== FileSystemWritableFileStream =====
  // 采用分块流式传输，避免大文件全量 base64 驻留内存
  // 每当缓冲超过 CHUNK_SIZE 就自动透过 rc_fs_write_chunk 推送一块

  var FS_CHUNK_SIZE = 4 * 1024 * 1024; // 4 MB

  function FileSystemWritableFileStream(path) {
    this._path = path;
    this._buffer = [];    // 待推送的内存块
    this._bufferedLen = 0; // 当前内存块总字节数
    this._position = 0;   // 当前负责转换为共识写入位置（seek 用）
    this._flushedBytes = 0; // 已向 Flutter 层推送的字节数
    this._closed = false;
  }

  // 将当前内存块合并成一个 Uint8Array
  FileSystemWritableFileStream.prototype._combineBuffer = function() {
    if (this._buffer.length === 0) return new Uint8Array(0);
    if (this._buffer.length === 1) return this._buffer[0];
    var totalLen = 0;
    for (var i = 0; i < this._buffer.length; i++) totalLen += this._buffer[i].length;
    var result = new Uint8Array(totalLen);
    var offset = 0;
    for (var j = 0; j < this._buffer.length; j++) {
      result.set(this._buffer[j], offset);
      offset += this._buffer[j].length;
    }
    return result;
  };

  // 当内存块超过 CHUNK_SIZE 时自动 flush
  FileSystemWritableFileStream.prototype._maybeFlush = async function() {
    while (this._bufferedLen >= FS_CHUNK_SIZE) {
      var combined = this._combineBuffer();
      var chunk = combined.slice(0, FS_CHUNK_SIZE);
      var rest  = combined.slice(FS_CHUNK_SIZE);
      this._buffer = rest.length > 0 ? [rest] : [];
      this._bufferedLen = rest.length;

      var b64 = arrayBufferToBase64(chunk.buffer);
      var result = await callFlutter('rc_fs_write_chunk', {
        path: this._path,
        data: b64,
        offset: this._flushedBytes
      });
      if (result && result.error) {
        throw new Error('Failed to write chunk: ' + result.error);
      }
      this._flushedBytes += chunk.length;
    }
  };

  FileSystemWritableFileStream.prototype.write = async function(data) {
    if (this._closed) throw new TypeError('Stream is closed');

    var chunk;
    var writePosition = this._position;

    // 处理 WriteParams 对象
    if (data && typeof data === 'object' && data.type) {
      if (data.type === 'seek') {
        // seek 需要先将现有缓冲尤共陆顶再设置位置（简化实现）
        this._position = data.position || 0;
        return;
      }
      if (data.type === 'truncate') {
        // flush 当前缓冲，再请求截断
        await this._flush();
        var result = await callFlutter('rc_fs_truncate', {
          path: this._path,
          size: data.size || 0
        });
        if (result && result.error) throw new Error('Failed to truncate: ' + result.error);
        this._flushedBytes = Math.min(this._flushedBytes, data.size || 0);
        this._position = Math.min(this._position, data.size || 0);
        return;
      }
      // type === 'write'
      if (data.position !== undefined && data.position !== null) {
        writePosition = data.position;
      }
      data = data.data;
    }

    // 转换各种数据类型为 Uint8Array
    if (typeof data === 'string') {
      chunk = new TextEncoder().encode(data);
    } else if (data instanceof Blob) {
      chunk = new Uint8Array(await data.arrayBuffer());
    } else if (data instanceof ArrayBuffer) {
      chunk = new Uint8Array(data);
    } else if (ArrayBuffer.isView(data)) {
      chunk = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    } else if (data == null) {
      return;
    } else {
      chunk = new TextEncoder().encode(String(data));
    }

    // 逐逐写入缓冲（对 seek 展开数据中间的区域会填零）
    if (writePosition !== this._position + this._bufferedLen &&
        writePosition !== this._flushedBytes + this._bufferedLen) {
      // 有非顺序写入：先 flush 已缓冲数据
      await this._flush();
    }
    this._buffer.push(chunk);
    this._bufferedLen += chunk.length;
    this._position = writePosition + chunk.length;
    await this._maybeFlush();
  };

  // 将内存剩余全部推送
  FileSystemWritableFileStream.prototype._flush = async function() {
    if (this._bufferedLen === 0) return;
    var combined = this._combineBuffer();
    this._buffer = [];
    this._bufferedLen = 0;
    var b64 = arrayBufferToBase64(combined.buffer);
    var result = await callFlutter('rc_fs_write_chunk', {
      path: this._path,
      data: b64,
      offset: this._flushedBytes
    });
    if (result && result.error) throw new Error('Failed to write chunk: ' + result.error);
    this._flushedBytes += combined.length;
  };

  FileSystemWritableFileStream.prototype.seek = function(position) {
    if (this._closed) throw new TypeError('Stream is closed');
    this._position = position;
    return Promise.resolve();
  };

  FileSystemWritableFileStream.prototype.truncate = function(size) {
    if (this._closed) throw new TypeError('Stream is closed');
    return this.write({ type: 'truncate', size: size });
  };

  FileSystemWritableFileStream.prototype.close = async function() {
    if (this._closed) return;
    this._closed = true;

    // 先将剩余缓冲数据全部推送
    await this._flush();

    // 然后通知 Flutter 层关闭文件句柄
    var result = await callFlutter('rc_fs_write_close', {
      path: this._path,
      totalBytes: this._flushedBytes
    });
    if (result && result.error) {
      throw new Error('Failed to close file: ' + result.error);
    }
  };

  FileSystemWritableFileStream.prototype.abort = async function() {
    if (this._closed) return;
    this._closed = true;
    this._buffer = [];
    this._bufferedLen = 0;
    // 通知 Flutter 层丢弃正在写入的文件
    await callFlutter('rc_fs_write_abort', { path: this._path }).catch(function() {});
  };

  // ===== FileSystemFileHandle =====

  function FileSystemFileHandle(name, path) {
    FileSystemHandle.call(this, 'file', name, path);
  }

  FileSystemFileHandle.prototype = Object.create(FileSystemHandle.prototype);
  FileSystemFileHandle.prototype.constructor = FileSystemFileHandle;

  FileSystemFileHandle.prototype.getFile = async function() {
    var result = await callFlutter('rc_fs_read_file', { path: this._path });
    if (!result || result.error) {
      throw new DOMException(
        (result && result.error) || 'Failed to read file',
        'NotFoundError'
      );
    }

    var bytes = base64ToUint8Array(result.content);
    return new File([bytes], result.name || this.name, {
      type: result.mimeType || 'application/octet-stream',
      lastModified: result.lastModified || Date.now()
    });
  };

  FileSystemFileHandle.prototype.createWritable = function(options) {
    // options.keepExistingData は现時点では未実装（常に空から书き込み）
    return Promise.resolve(new FileSystemWritableFileStream(this._path));
  };

  // ===== FileSystemDirectoryHandle =====

  function FileSystemDirectoryHandle(name, path) {
    FileSystemHandle.call(this, 'directory', name, path);
  }

  FileSystemDirectoryHandle.prototype = Object.create(FileSystemHandle.prototype);
  FileSystemDirectoryHandle.prototype.constructor = FileSystemDirectoryHandle;

  // 异步迭代器：entries()
  FileSystemDirectoryHandle.prototype.entries = function() {
    var self = this;
    var fetched = false;
    var items = [];
    var index = 0;

    return {
      [Symbol.asyncIterator]: function() { return this; },
      next: async function() {
        if (!fetched) {
          fetched = true;
          var result = await callFlutter('rc_fs_list_dir', { path: self._path });
          if (result && Array.isArray(result)) {
            items = result;
          }
        }
        if (index >= items.length) {
          return { done: true, value: undefined };
        }
        var entry = items[index++];
        var handle = entry.kind === 'directory'
          ? new FileSystemDirectoryHandle(entry.name, entry.path)
          : new FileSystemFileHandle(entry.name, entry.path);
        return { done: false, value: [entry.name, handle] };
      }
    };
  };

  // 异步迭代器：keys()
  FileSystemDirectoryHandle.prototype.keys = function() {
    var entriesIter = this.entries();
    var innerIter = entriesIter[Symbol.asyncIterator]();
    return {
      [Symbol.asyncIterator]: function() { return this; },
      next: async function() {
        var result = await innerIter.next();
        if (result.done) return { done: true, value: undefined };
        return { done: false, value: result.value[0] };
      }
    };
  };

  // 异步迭代器：values()
  FileSystemDirectoryHandle.prototype.values = function() {
    var entriesIter = this.entries();
    var innerIter = entriesIter[Symbol.asyncIterator]();
    return {
      [Symbol.asyncIterator]: function() { return this; },
      next: async function() {
        var result = await innerIter.next();
        if (result.done) return { done: true, value: undefined };
        return { done: false, value: result.value[1] };
      }
    };
  };

  // 支持 for await...of 直接迭代 DirectoryHandle
  FileSystemDirectoryHandle.prototype[Symbol.asyncIterator] = function() {
    return this.entries()[Symbol.asyncIterator]();
  };

  FileSystemDirectoryHandle.prototype.getFileHandle = async function(name, options) {
    var create = (options && options.create) || false;
    var result = await callFlutter('rc_fs_get_handle', {
      parentPath: this._path,
      name: name,
      kind: 'file',
      create: create
    });
    if (!result || result.error) {
      throw new DOMException(
        (result && result.error) || 'File not found: ' + name,
        'NotFoundError'
      );
    }
    return new FileSystemFileHandle(result.name, result.path);
  };

  FileSystemDirectoryHandle.prototype.getDirectoryHandle = async function(name, options) {
    var create = (options && options.create) || false;
    var result = await callFlutter('rc_fs_get_handle', {
      parentPath: this._path,
      name: name,
      kind: 'directory',
      create: create
    });
    if (!result || result.error) {
      throw new DOMException(
        (result && result.error) || 'Directory not found: ' + name,
        'NotFoundError'
      );
    }
    return new FileSystemDirectoryHandle(result.name, result.path);
  };

  FileSystemDirectoryHandle.prototype.removeEntry = async function(name, options) {
    var recursive = (options && options.recursive) || false;
    var result = await callFlutter('rc_fs_remove_entry', {
      parentPath: this._path,
      name: name,
      recursive: recursive
    });
    if (result && result.error) {
      throw new DOMException(result.error, 'NotFoundError');
    }
  };

  FileSystemDirectoryHandle.prototype.resolve = async function(possibleDescendant) {
    if (!possibleDescendant || !possibleDescendant._path) return null;
    var parentPath = this._path.replace(/[\/\\]$/, '');
    var childPath = possibleDescendant._path.replace(/[\/\\]$/, '');
    // 标准化分隔符
    parentPath = parentPath.replace(/\\/g, '/');
    childPath = childPath.replace(/\\/g, '/');
    if (!childPath.startsWith(parentPath + '/')) return null;
    var relative = childPath.substring(parentPath.length + 1);
    return relative.split('/');
  };

  // ===== Picker API =====

  window.showSaveFilePicker = async function(options) {
    var opts = options || {};
    var result = await callFlutter('rc_fs_save_picker', {
      suggestedName: opts.suggestedName || '',
      types: opts.types || null,
      excludeAcceptAllOption: opts.excludeAcceptAllOption || false
    });
    if (!result || result.cancelled) {
      throw new DOMException('The user aborted a request.', 'AbortError');
    }
    return new FileSystemFileHandle(result.name, result.path);
  };

  window.showOpenFilePicker = async function(options) {
    var opts = options || {};
    var result = await callFlutter('rc_fs_open_picker', {
      multiple: opts.multiple || false,
      types: opts.types || null,
      excludeAcceptAllOption: opts.excludeAcceptAllOption || false
    });
    if (!result || result.cancelled) {
      throw new DOMException('The user aborted a request.', 'AbortError');
    }
    var files = result.files || [];
    var handles = [];
    for (var i = 0; i < files.length; i++) {
      handles.push(new FileSystemFileHandle(files[i].name, files[i].path));
    }
    return handles;
  };

  window.showDirectoryPicker = async function(options) {
    var result = await callFlutter('rc_fs_dir_picker', options || {});
    if (!result || result.cancelled) {
      throw new DOMException('The user aborted a request.', 'AbortError');
    }
    return new FileSystemDirectoryHandle(result.name, result.path);
  };
})();
""";
}
