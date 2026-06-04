import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 文件系统相关的 JS polyfill 和 Handler 注册
mixin FileSystemMixin {
  // Android 文件保存：临时路径 → 原始文件名映射
  // showSaveFilePicker 在 Android 上先写入缓存目录，close() 后通过 FilePicker.saveFile(bytes) 导出
  final Map<String, String> _pendingSaveExports = {};

  // 分块写入：追踪当前打开的 RandomAccessFile 句柄（路径 → 句柄）
  final Map<String, RandomAccessFile> _openWriteFiles = {};

  /// 注入 JS：覆盖 File System Access API，桥接到 Flutter
  static const String polyfillJS = r"""
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
    // options.keepExistingData は現時点では未実装（常に空から書き込み）
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

  /// 注册文件系统 Handler
  void registerFileSystemHandlers(InAppWebViewController controller) {
    // 保存文件选择器
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_save_picker',
      callback: (args) async {
        try {
          final data = args.isNotEmpty ? args[0] as Map<dynamic, dynamic>? : null;
          final suggestedName = data?['suggestedName'] as String? ?? '';
          final types = data?['types'] as List?;

          // 从 types 中提取允许的扩展名
          List<String>? allowedExtensions;
          if (types != null) {
            final exts = <String>[];
            for (final t in types) {
              final accept = (t as Map?)?['accept'] as Map?;
              if (accept == null) continue;
              for (final patterns in accept.values) {
                if (patterns is List) {
                  for (final p in patterns) {
                    if (p is String) {
                      exts.add(p.replaceFirst(RegExp(r'^\.'), ''));
                    }
                  }
                }
              }
            }
            if (exts.isNotEmpty) allowedExtensions = exts;
          }

          if (Platform.isAndroid) {
            // Android: FilePicker.saveFile() 需要 bytes 参数才能工作，
            // 但此时文件数据尚未就绪（JS 端在 close() 时才发送）。
            // 策略：先返回应用缓存目录的临时路径（dart:io 有完整写入权限），
            // 在 rc_fs_write_file 完成写入后自动触发 FilePicker.saveFile(bytes) 导出。
            final fileName = suggestedName.isNotEmpty
                ? suggestedName
                : 'file_${DateTime.now().millisecondsSinceEpoch}';
            final cacheDir = await getTemporaryDirectory();
            final tempPath = '${cacheDir.path}${Platform.pathSeparator}fs_export_$fileName';
            // 记录到待导出映射
            _pendingSaveExports[tempPath] = fileName;
            return {'path': tempPath, 'name': fileName};
          } else {
            // Windows / 桌面平台：saveFile() 直接返回用户选择的路径
            final result = await FilePicker.saveFile(
              dialogTitle: '保存文件',
              fileName: suggestedName.isNotEmpty ? suggestedName : null,
              type: allowedExtensions != null ? FileType.custom : FileType.any,
              allowedExtensions: allowedExtensions,
            );

            if (result == null) {
              return {'cancelled': true};
            }

            final name = result.split(Platform.pathSeparator).last;
            return {'path': result, 'name': name};
          }
        } catch (e) {
          debugPrint('rc_fs_save_picker error: $e');
          return {'cancelled': true, 'error': e.toString()};
        }
      },
    );

    // 打开文件选择器
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_open_picker',
      callback: (args) async {
        try {
          final data = args.isNotEmpty ? args[0] as Map<dynamic, dynamic>? : null;
          final multiple = data?['multiple'] as bool? ?? false;
          final types = data?['types'] as List?;

          List<String>? allowedExtensions;
          final mimeTypes = <String>{};
          if (types != null) {
            final exts = <String>[];
            for (final t in types) {
              final accept = (t as Map?)?['accept'] as Map?;
              if (accept == null) continue;
              for (final entry in accept.entries) {
                // 收集 MIME 类型（如 image/*, video/*, audio/*）
                if (entry.key is String) {
                  mimeTypes.add((entry.key as String).toLowerCase());
                }
                final patterns = entry.value;
                if (patterns is List) {
                  for (final p in patterns) {
                    if (p is String) {
                      exts.add(p.replaceFirst(RegExp(r'^\.'), ''));
                    }
                  }
                }
              }
            }
            if (exts.isNotEmpty) allowedExtensions = exts;
          }

          // 根据 MIME 类型智能选择 FileType，使 Android 端能显示
          // 相册、音乐、视频等系统媒体分类，而不仅仅是文件管理器
          FileType fileType;
          if (mimeTypes.every((m) => m.startsWith('image/'))) {
            fileType = FileType.image;
            allowedExtensions = null; // FileType.image 不需要扩展名过滤
          } else if (mimeTypes.every((m) => m.startsWith('video/'))) {
            fileType = FileType.video;
            allowedExtensions = null;
          } else if (mimeTypes.every((m) => m.startsWith('audio/'))) {
            fileType = FileType.audio;
            allowedExtensions = null;
          } else if (mimeTypes.isNotEmpty && mimeTypes.every((m) =>
              m.startsWith('image/') || m.startsWith('video/'))) {
            // 同时包含图片和视频时使用 media 类型
            fileType = FileType.media;
            allowedExtensions = null;
          } else if (allowedExtensions != null) {
            fileType = FileType.custom;
          } else {
            fileType = FileType.any;
          }

          final result = await FilePicker.pickFiles(
            allowMultiple: multiple,
            type: fileType,
            allowedExtensions: allowedExtensions,
          );

          if (result == null || result.files.isEmpty) {
            return {'cancelled': true};
          }

          final files = <Map<String, dynamic>>[];
          for (final f in result.files) {
            if (f.path != null) {
              files.add({
                'path': f.path!,
                'name': f.name,
                'size': f.size,
              });
            }
          }

          return {'files': files};
        } catch (e) {
          debugPrint('rc_fs_open_picker error: $e');
          return {'cancelled': true, 'error': e.toString()};
        }
      },
    );

    // 目录选择器
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_dir_picker',
      callback: (args) async {
        try {
          final result = await FilePicker.getDirectoryPath(
            dialogTitle: '选择目录',
          );

          if (result == null) {
            return {'cancelled': true};
          }

          final name = result.split(Platform.pathSeparator).last;
          return {'path': result, 'name': name};
        } catch (e) {
          debugPrint('rc_fs_dir_picker error: $e');
          return {'cancelled': true, 'error': e.toString()};
        }
      },
    );

    // 读取文件内容
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_read_file',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          if (path == null || path.isEmpty) return {'error': 'Missing path'};

          final file = File(path);
          if (!await file.exists()) {
            return {'error': 'File not found: $path'};
          }

          final bytes = await file.readAsBytes();
          final stat = await file.stat();
          final name = path.split(Platform.pathSeparator).last;

          // 推断 MIME 类型
          String mimeType = 'application/octet-stream';
          final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
          const mimeMap = {
            'txt': 'text/plain',
            'html': 'text/html',
            'htm': 'text/html',
            'css': 'text/css',
            'js': 'application/javascript',
            'json': 'application/json',
            'xml': 'application/xml',
            'csv': 'text/csv',
            'md': 'text/markdown',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'gif': 'image/gif',
            'svg': 'image/svg+xml',
            'webp': 'image/webp',
            'ico': 'image/x-icon',
            'pdf': 'application/pdf',
            'zip': 'application/zip',
            'mp3': 'audio/mpeg',
            'mp4': 'video/mp4',
            'wav': 'audio/wav',
            'webm': 'video/webm',
            'woff': 'font/woff',
            'woff2': 'font/woff2',
            'ttf': 'font/ttf',
            'otf': 'font/otf',
          };
          if (mimeMap.containsKey(ext)) {
            mimeType = mimeMap[ext]!;
          }

          return {
            'content': base64Encode(bytes),
            'size': bytes.length,
            'name': name,
            'lastModified': stat.modified.millisecondsSinceEpoch,
            'mimeType': mimeType,
          };
        } catch (e) {
          debugPrint('rc_fs_read_file error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // ── 分块写入第一步：接收一个数据块，按 offset 写入文件 ──
    // JS 侧每积累 4 MB 调用一次，offset 为已确认写入的字节偏移
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_write_chunk',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          final base64Data = data['data'] as String?;
          final offset = (data['offset'] as num?)?.toInt() ?? 0;
          if (path == null || path.isEmpty) return {'error': 'Missing path'};
          if (base64Data == null) return {'error': 'Missing data'};

          final bytes = base64Decode(base64Data);

          RandomAccessFile raf;
          if (_openWriteFiles.containsKey(path)) {
            raf = _openWriteFiles[path]!;
          } else {
            // 首个分块：创建/截断文件并打开句柄
            final file = File(path);
            final parent = file.parent;
            if (!await parent.exists()) {
              await parent.create(recursive: true);
            }
            raf = await file.open(mode: FileMode.write);
            _openWriteFiles[path] = raf;
          }

          await raf.setPosition(offset);
          await raf.writeFrom(bytes);
          return {'success': true, 'bytesWritten': bytes.length};
        } catch (e) {
          debugPrint('rc_fs_write_chunk error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // ── 分块写入第二步：所有块发送完毕，关闭文件句柄 ──
    // Android 的 showSaveFilePicker pending export 也在此处理
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_write_close',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          final totalBytes = (data['totalBytes'] as num?)?.toInt() ?? 0;
          if (path == null || path.isEmpty) return {'error': 'Missing path'};

          // 关闭 RandomAccessFile 句柄
          final raf = _openWriteFiles.remove(path);
          await raf?.close();

          // Android：若为 showSaveFilePicker 产生的待导出文件，触发系统保存对话框
          if (Platform.isAndroid && _pendingSaveExports.containsKey(path)) {
            final exportFileName = _pendingSaveExports.remove(path)!;
            List<String>? allowedExts;
            final dotIdx = exportFileName.lastIndexOf('.');
            if (dotIdx > 0) {
              allowedExts = [exportFileName.substring(dotIdx + 1)];
            }
            final fileBytes = await File(path).readAsBytes();
            final savedPath = await FilePicker.saveFile(
              dialogTitle: '保存文件',
              fileName: exportFileName,
              bytes: Uint8List.fromList(fileBytes),
              type: allowedExts != null ? FileType.custom : FileType.any,
              allowedExtensions: allowedExts,
            );
            // 清理临时文件
            try { await File(path).delete(); } catch (_) {}
            if (savedPath == null) {
              return {'error': 'User cancelled save'};
            }
          }

          return {'success': true, 'bytesWritten': totalBytes};
        } catch (e) {
          debugPrint('rc_fs_write_close error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // ── 用户取消写入：关闭句柄并删除不完整文件 ──
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_write_abort',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          if (path == null || path.isEmpty) return {'error': 'Missing path'};

          final raf = _openWriteFiles.remove(path);
          await raf?.close();
          _pendingSaveExports.remove(path);

          // 删除残留的不完整文件
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {}
          return {'success': true};
        } catch (e) {
          debugPrint('rc_fs_write_abort error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // ── FileSystemWritableFileStream.truncate() 支持 ──
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_truncate',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          final size = (data['size'] as num?)?.toInt() ?? 0;
          if (path == null || path.isEmpty) return {'error': 'Missing path'};

          final raf = _openWriteFiles[path];
          if (raf != null) {
            // 文件已由当前句柄打开，直接截断
            await raf.truncate(size);
          } else {
            // 文件未打开（极少数情况），临时打开截断后关闭
            final file = File(path);
            if (await file.exists()) {
              final r = await file.open(mode: FileMode.append);
              await r.truncate(size);
              await r.close();
            }
          }
          return {'success': true};
        } catch (e) {
          debugPrint('rc_fs_truncate error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 列出目录内容
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_list_dir',
      callback: (args) async {
        try {
          if (args.isEmpty) return [];
          final data = args[0] as Map<dynamic, dynamic>;
          final path = data['path'] as String?;
          if (path == null || path.isEmpty) return [];

          final dir = Directory(path);
          if (!await dir.exists()) return [];

          final entries = <Map<String, dynamic>>[];
          await for (final entity in dir.list()) {
            final name = entity.path.split(Platform.pathSeparator).last;
            entries.add({
              'name': name,
              'kind': entity is Directory ? 'directory' : 'file',
              'path': entity.path,
            });
          }
          return entries;
        } catch (e) {
          debugPrint('rc_fs_list_dir error: $e');
          return [];
        }
      },
    );

    // 获取/创建子文件或子目录 handle
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_get_handle',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final parentPath = data['parentPath'] as String?;
          final name = data['name'] as String?;
          final kind = data['kind'] as String? ?? 'file';
          final create = data['create'] as bool? ?? false;
          if (parentPath == null || name == null) {
            return {'error': 'Missing parentPath or name'};
          }

          final fullPath = '$parentPath${Platform.pathSeparator}$name';

          if (kind == 'directory') {
            final dir = Directory(fullPath);
            if (await dir.exists()) {
              return {'path': fullPath, 'name': name, 'kind': 'directory'};
            }
            if (create) {
              await dir.create(recursive: true);
              return {'path': fullPath, 'name': name, 'kind': 'directory'};
            }
            return {'error': 'Directory not found: $name'};
          } else {
            final file = File(fullPath);
            if (await file.exists()) {
              return {'path': fullPath, 'name': name, 'kind': 'file'};
            }
            if (create) {
              // 确保父目录存在
              final parent = file.parent;
              if (!await parent.exists()) {
                await parent.create(recursive: true);
              }
              await file.create();
              return {'path': fullPath, 'name': name, 'kind': 'file'};
            }
            return {'error': 'File not found: $name'};
          }
        } catch (e) {
          debugPrint('rc_fs_get_handle error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 删除文件或目录
    controller.addJavaScriptHandler(
      handlerName: 'rc_fs_remove_entry',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final parentPath = data['parentPath'] as String?;
          final name = data['name'] as String?;
          final recursive = data['recursive'] as bool? ?? false;
          if (parentPath == null || name == null) {
            return {'error': 'Missing parentPath or name'};
          }

          final fullPath = '$parentPath${Platform.pathSeparator}$name';

          final dir = Directory(fullPath);
          if (await dir.exists()) {
            await dir.delete(recursive: recursive);
            return {'success': true};
          }

          final file = File(fullPath);
          if (await file.exists()) {
            await file.delete();
            return {'success': true};
          }

          return {'error': 'Entry not found: $name'};
        } catch (e) {
          debugPrint('rc_fs_remove_entry error: $e');
          return {'error': e.toString()};
        }
      },
    );
  }

  /// 释放所有打开的文件写入句柄（WebView dispose 时调用）
  void disposeFileSystem() {
    for (final raf in _openWriteFiles.values) {
      try { raf.closeSync(); } catch (_) {}
    }
    _openWriteFiles.clear();
    _pendingSaveExports.clear();
  }
}
