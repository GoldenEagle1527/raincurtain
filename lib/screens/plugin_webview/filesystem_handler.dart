import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'webview_scripts.dart';

/// 文件系统相关的 JS polyfill 和 Handler 注册
mixin FileSystemMixin {
  // Android 文件保存：临时路径 → 原始文件名映射
  // showSaveFilePicker 在 Android 上先写入缓存目录，close() 后通过 FilePicker.saveFile(bytes) 导出
  final Map<String, String> _pendingSaveExports = {};

  // 分块写入：追踪当前打开的 RandomAccessFile 句柄（路径 → 句柄）
  final Map<String, RandomAccessFile> _openWriteFiles = {};

  /// 注入 JS：覆盖 File System Access API，桥接到 Flutter
  static const String polyfillJS = WebViewScripts.fileSystemPolyfillJS;

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
