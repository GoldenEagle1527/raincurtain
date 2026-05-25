import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'database_manager.dart';
import 'plugin_manifest.dart';
import 'plugin_icon.dart';
import 'plugin_storage_manager.dart';

class LocalPlugin {
  final String entryPath;
  final PluginManifest manifest;

  const LocalPlugin({
    required this.entryPath,
    required this.manifest,
  });

  String get id => manifest.id;
  String get name => manifest.name;
  String get description => manifest.description;
  String get version => manifest.version;
  String get author => manifest.author;

  // 新增：获取图标绝对路径（仅对 PluginImageIcon 有效）
  String? get iconAbsolutePath {
    if (manifest.icon is PluginImageIcon) {
      final relativePath = (manifest.icon as PluginImageIcon).relativePath;
      return p.join(entryPath, relativePath);
    }
    return null;
  }


  Map<String, dynamic> toJson() => {
    'entryPath': entryPath,
    'manifest': manifest.toJson(),
  };

  factory LocalPlugin.fromJson(Map<String, dynamic> json) {
    return LocalPlugin(
      entryPath: (json['entryPath'] ?? '').toString(),
      manifest: PluginManifest.fromJson(
        Map<String, dynamic>.from(json['manifest'] as Map),
      ),
    );
  }
}

class PluginManager extends ChangeNotifier {
  List<LocalPlugin> _plugins = [];
  List<LocalPlugin> get plugins => _plugins;

  bool _isInit = false;
  bool get isInit => _isInit;

  late Directory sandboxDir;
  final Uuid _uuid = const Uuid();

  PluginManager() {
    _init();
  }

  Future<void> _init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      sandboxDir = Directory(p.join(supportDir.path, 'RainCurtainPlugins'));
      if (!await sandboxDir.exists()) {
        await sandboxDir.create(recursive: true);
      }
      await _loadPlugins();
    } catch (e, stackTrace) {
      debugPrint('PluginManager init failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _plugins = [];

      if (!_isSandboxDirReady) {
        final fallbackDir = Directory(p.join(Directory.systemTemp.path, 'RainCurtainPlugins'));
        if (!await fallbackDir.exists()) {
          await fallbackDir.create(recursive: true);
        }
        sandboxDir = fallbackDir;
      }
    } finally {
      _isInit = true;
      notifyListeners();
    }
  }

  Future<void> _loadPlugins() async {
    final db = DatabaseManager.database;
    final rows = await db.query('plugins', orderBy: 'sort_order ASC');
    final List<LocalPlugin> loaded = [];

    for (final row in rows) {
      final entryPath = row['entry_path'] as String;
      if (entryPath.isEmpty) continue;

      try {
        // manifest.yml 与 index.html 在同一目录
        final entryFile = File(p.join(sandboxDir.path, entryPath));
        final manifestFile = File(p.join(entryFile.parent.path, 'manifest.yml'));

        if (!await manifestFile.exists()) {
          debugPrint('manifest.yml not found for entryPath: $entryPath');
          continue;
        }

        final manifest = await _readManifest(manifestFile);
        loaded.add(LocalPlugin(entryPath: entryPath, manifest: manifest));

        // 确保插件的存储表存在
        if (manifest.storage.isNotEmpty) {
          await PluginStorageManager.instance.ensureTablesForPlugin(
              manifest.id, manifest.storage);
        }
      } catch (err) {
        debugPrint('Failed to load plugin ($entryPath): $err');
      }
    }

    _plugins = loaded;
  }

  /// 重新从磁盘读取并加载插件列表
  Future<void> reloadPlugins() async {
    try {
      await _loadPlugins();
    } catch (e) {
      debugPrint('reloadPlugins failed: $e');
    }
    notifyListeners();
  }

  Future<void> _savePlugins() async {
    final db = DatabaseManager.database;
    await db.transaction((txn) async {
      // 清空后重新插入
      await txn.delete('plugins');
      final batch = txn.batch();
      for (int i = 0; i < _plugins.length; i++) {
        final plugin = _plugins[i];
        batch.insert('plugins', {
          'plugin_id': plugin.id,
          'entry_path': plugin.entryPath,
          'manifest_json': jsonEncode(plugin.manifest.toJson()),
          'sort_order': i,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> installPlugin({
    Future<bool> Function(LocalPlugin existingPlugin, PluginManifest newManifest)? onConflict,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    final zipFile = File(result.files.single.path!);
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final tempDir = Directory(p.join(Directory.systemTemp.path, _uuid.v7()));
    await tempDir.create(recursive: true);

    try {
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(tempDir.path, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory(p.join(tempDir.path, filename)).create(recursive: true);
        }
      }

      final manifestFile = await _findManifestFile(tempDir);
      if (manifestFile == null) {
        throw Exception('插件格式无效：缺少 manifest.yml 文件');
      }

      final manifest = await _readManifest(manifestFile);
      final pluginId = manifest.id;
      
      // 检查是否已存在
      final existingPlugin = _plugins.cast<LocalPlugin?>().firstWhere(
        (p) => p?.id == pluginId,
        orElse: () => null,
      );
      
      if (existingPlugin != null) {
        // 如果提供了冲突处理回调，调用它
        if (onConflict != null) {
          final shouldOverwrite = await onConflict(existingPlugin, manifest);
          if (!shouldOverwrite) {
            // 用户取消，清理临时目录
            if (await tempDir.exists()) {
              await tempDir.delete(recursive: true);
            }
            return;
          }
        } else {
          // 没有提供回调，默认抛出异常
          throw Exception('插件已存在：$pluginId');
        }
        
        // 删除旧插件目录
        final oldPluginDir = Directory(p.join(sandboxDir.path, pluginId));
        if (await oldPluginDir.exists()) {
          await oldPluginDir.delete(recursive: true);
        }
        
        // 从列表中移除旧插件
        _plugins.removeWhere((p) => p.id == pluginId);
      }

      final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
      await tempDir.rename(pluginDir.path);

      final entryPath = await _findEntryPath(pluginDir, pluginId);

      final newPlugin = LocalPlugin(
        entryPath: entryPath,
        manifest: manifest,
      );

      _plugins.add(newPlugin);
      await _savePlugins();

      // 创建插件的存储表
      if (manifest.storage.isNotEmpty) {
        await PluginStorageManager.instance.ensureTablesForPlugin(
            manifest.id, manifest.storage);
      }

      notifyListeners();
    } catch (_) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<File?> _findManifestFile(Directory pluginDir) async {
    final entities = await pluginDir.list(recursive: false).toList();

    for (final entity in entities) {
      if (entity is File && p.basename(entity.path) == 'manifest.yml') {
        return entity;
      }
      if (entity is Directory) {
        final manifestInSubDir = File(p.join(entity.path, 'manifest.yml'));
        if (await manifestInSubDir.exists()) {
          return manifestInSubDir;
        }
      }
    }

    return null;
  }

  Future<PluginManifest> _readManifest(File manifestFile) async {
    try {
      final content = await manifestFile.readAsString();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) {
        throw const FormatException('manifest.yml 内容必须是对象结构');
      }
      return PluginManifest.fromYamlMap(yaml);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('manifest.yml 解析失败：$e');
    }
  }

  Future<String> _findEntryPath(Directory pluginDir, String pluginId) async {
    final entities = await pluginDir.list(recursive: false).toList();

    for (final entity in entities) {
      if (entity is File && p.basename(entity.path) == 'index.html') {
        return '$pluginId/index.html';
      }
      if (entity is Directory) {
        final subEntities = await entity.list(recursive: false).toList();
        for (final subEntity in subEntities) {
          if (subEntity is File && p.basename(subEntity.path) == 'index.html') {
            final subDirName = p.basename(entity.path);
            return '$pluginId/$subDirName/index.html';
          }
        }
      }
    }

    throw Exception('插件格式无效：根目录或一级子目录中未找到 index.html');
  }

  bool get _isSandboxDirReady {
    try {
      return sandboxDir.path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 拖拽排序插件列表
  /// [oldIndex] 和 [newIndex] 来自 ReorderableListView.onReorder
  Future<void> reorderPlugins(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1; // ReorderableListView 的标准偏移处理
    }
    if (oldIndex < 0 || oldIndex >= _plugins.length ||
        newIndex < 0 || newIndex >= _plugins.length) return;
    final item = _plugins.removeAt(oldIndex);
    _plugins.insert(newIndex, item);
    await _savePlugins();
    notifyListeners();
  }

  Future<void> uninstallPlugin(String pluginId) async {
    final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
    }
    // 清理插件的存储表
    await PluginStorageManager.instance.dropTablesForPlugin(pluginId);

    _plugins.removeWhere((p) => p.id == pluginId);
    await _savePlugins();
    notifyListeners();
  }

}
