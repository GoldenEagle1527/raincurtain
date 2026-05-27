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
  /// 同时扫描沙箱目录，发现未注册到数据库的新插件并自动注册
  Future<void> reloadPlugins() async {
    try {
      await _scanAndRegisterNewPlugins();
      await _loadPlugins();
    } catch (e) {
      debugPrint('reloadPlugins failed: $e');
    }
    notifyListeners();
  }

  /// 扫描沙箱目录，将磁盘上存在但数据库中未注册的插件自动注册
  Future<void> _scanAndRegisterNewPlugins() async {
    if (!await sandboxDir.exists()) return;

    final db = DatabaseManager.database;
    // 获取数据库中已注册的 plugin_id 集合
    final rows = await db.query('plugins', columns: ['plugin_id']);
    final registeredIds = rows.map((r) => r['plugin_id'] as String).toSet();

    // 获取当前最大 sort_order
    final maxOrderResult = await db.rawQuery('SELECT MAX(sort_order) as max_order FROM plugins');
    int nextOrder = (maxOrderResult.first['max_order'] as int? ?? -1) + 1;

    // 扫描沙箱目录的一级子目录（每个子目录是一个 pluginId）
    final entities = await sandboxDir.list().toList();
    for (final entity in entities) {
      if (entity is! Directory) continue;

      final pluginIdDir = entity;
      final pluginId = p.basename(pluginIdDir.path);

      // 跳过已注册的
      if (registeredIds.contains(pluginId)) continue;

      // 尝试在此目录下找到 manifest.yml
      try {
        final manifestFile = await _findManifestInPluginDir(pluginIdDir);
        if (manifestFile == null) continue;

        final manifest = await _readManifest(manifestFile);
        final entryPath = await _findEntryPathInDir(pluginIdDir, pluginId);
        if (entryPath == null) continue;

        // 注册到数据库
        await db.insert('plugins', {
          'plugin_id': manifest.id.isNotEmpty ? manifest.id : pluginId,
          'entry_path': entryPath,
          'manifest_json': jsonEncode(manifest.toJson()),
          'sort_order': nextOrder++,
        });

        debugPrint('Auto-registered plugin from disk: $pluginId');
      } catch (e) {
        debugPrint('Failed to auto-register plugin ($pluginId): $e');
      }
    }
  }

  /// 在插件 ID 目录中查找 manifest.yml（支持直接放在子目录中）
  Future<File?> _findManifestInPluginDir(Directory pluginIdDir) async {
    final subEntities = await pluginIdDir.list().toList();
    for (final sub in subEntities) {
      if (sub is Directory) {
        final manifestFile = File(p.join(sub.path, 'manifest.yml'));
        if (await manifestFile.exists()) {
          return manifestFile;
        }
      }
      if (sub is File && p.basename(sub.path) == 'manifest.yml') {
        return sub;
      }
    }
    return null;
  }

  /// 在插件 ID 目录中查找 entry path（index.html 的相对路径）
  Future<String?> _findEntryPathInDir(Directory pluginIdDir, String pluginId) async {
    final subEntities = await pluginIdDir.list().toList();
    for (final sub in subEntities) {
      if (sub is Directory) {
        final subDirName = p.basename(sub.path);
        final indexFile = File(p.join(sub.path, 'index.html'));
        if (await indexFile.exists()) {
          return '$pluginId/$subDirName/index.html';
        }
      }
      if (sub is File && p.basename(sub.path) == 'index.html') {
        return '$pluginId/index.html';
      }
    }
    return null;
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

  /// 根据 pluginId 查找已加载的插件
  LocalPlugin? getPluginById(String pluginId) {
    for (final p in _plugins) {
      if (p.id == pluginId) return p;
    }
    return null;
  }

  /// 从 zip 文件路径安装插件（无 UI 依赖，供 API 和 UI 共用）
  ///
  /// [overwrite] 为 true 时覆盖已存在的同 ID 插件，为 false 时抛异常。
  /// 返回安装成功的 [LocalPlugin]。
  Future<LocalPlugin> installPluginFromZip(
    File zipFile, {
    required bool overwrite,
  }) async {
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
      final existingPlugin = getPluginById(pluginId);

      if (existingPlugin != null) {
        if (!overwrite) {
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
      return newPlugin;
    } catch (_) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// 注册一个已存在于沙箱目录的插件（开发模式）
  ///
  /// 插件目录（或符号链接）必须已存在于 sandboxDir/{pluginId}/ 下。
  /// [entryPath] 格式为 "{pluginId}/{subdir}/index.html"。
  /// [overwrite] 为 true 时覆盖已存在的同 ID 插件。
  /// 返回注册成功的 [LocalPlugin]。
  Future<LocalPlugin> registerExistingPlugin({
    required String pluginId,
    required String entryPath,
    required bool overwrite,
  }) async {
    // 校验 entryPath 对应的文件存在
    final entryFile = File(p.join(sandboxDir.path, entryPath));
    if (!await entryFile.exists()) {
      throw Exception('入口文件不存在：$entryPath');
    }

    // 查找 manifest.yml（与 index.html 同目录）
    final manifestFile = File(p.join(entryFile.parent.path, 'manifest.yml'));
    if (!await manifestFile.exists()) {
      throw Exception('manifest.yml 不存在于入口文件同级目录');
    }

    final manifest = await _readManifest(manifestFile);

    // 校验 pluginId 与 manifest.id 一致
    if (manifest.id != pluginId) {
      throw Exception(
          'pluginId ($pluginId) 与 manifest.id (${manifest.id}) 不一致');
    }

    // 检查是否已存在
    final existingPlugin = getPluginById(pluginId);
    if (existingPlugin != null) {
      if (!overwrite) {
        throw Exception('插件已存在：$pluginId');
      }
      _plugins.removeWhere((p) => p.id == pluginId);
    }

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
    return newPlugin;
  }

  /// 重新读取单个插件的 manifest.yml（开发模式热更新）
  ///
  /// 返回更新后的 [LocalPlugin]，如果插件不存在返回 null。
  Future<LocalPlugin?> reloadPlugin(String pluginId) async {
    final idx = _plugins.indexWhere((p) => p.id == pluginId);
    if (idx == -1) return null;

    final oldPlugin = _plugins[idx];
    final entryFile = File(p.join(sandboxDir.path, oldPlugin.entryPath));
    final manifestFile = File(p.join(entryFile.parent.path, 'manifest.yml'));

    if (!await manifestFile.exists()) {
      throw Exception('manifest.yml 不存在：${oldPlugin.entryPath}');
    }

    final manifest = await _readManifest(manifestFile);
    final updatedPlugin = LocalPlugin(
      entryPath: oldPlugin.entryPath,
      manifest: manifest,
    );

    _plugins[idx] = updatedPlugin;
    await _savePlugins();

    // 确保存储表同步
    if (manifest.storage.isNotEmpty) {
      await PluginStorageManager.instance.ensureTablesForPlugin(
          manifest.id, manifest.storage);
    }

    notifyListeners();
    return updatedPlugin;
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

    // 检查是否已存在同 ID 的插件（只从 archive 中读 manifest，不全量解压）
    if (onConflict != null) {
      final manifest = await _readManifestFromZip(zipFile);
      if (manifest != null) {
        final existingPlugin = getPluginById(manifest.id);
        if (existingPlugin != null) {
          final shouldOverwrite = await onConflict(existingPlugin, manifest);
          if (!shouldOverwrite) {
            return;
          }
        }
      }
    }

    await installPluginFromZip(zipFile, overwrite: true);
  }

  /// 从 zip 文件中直接读取 manifest.yml（不解压全部文件到磁盘）
  Future<PluginManifest?> _readManifestFromZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (file.isFile && p.basename(file.name) == 'manifest.yml') {
        try {
          final content = utf8.decode(file.content as List<int>);
          final yaml = loadYaml(content);
          if (yaml is! YamlMap) continue;
          return PluginManifest.fromYamlMap(yaml);
        } catch (_) {
          continue;
        }
      }
    }
    return null;
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
