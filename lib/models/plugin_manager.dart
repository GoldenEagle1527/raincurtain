import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yaml/yaml.dart';

import 'database_manager.dart';
import 'plugin_manifest.dart';
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

  /// 插件文件即将被修改/删除时的通知回调（例如清理 SandboxServer 的数据库缓存）
  Future<void> Function(String pluginId)? onBeforePluginFileChange;

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

  Future<void> _loadPlugins({bool force = false}) async {
    final db = DatabaseManager.database;
    final rows = await db.query('plugins', orderBy: 'sort_order ASC');
    final List<LocalPlugin> loaded = [];

    for (final row in rows) {
      var entryPath = row['entry_path'] as String;
      final pluginId = row['plugin_id'] as String;
      if (entryPath.isEmpty) continue;

      try {
        // 兼容和迁移逻辑：
        if (entryPath.endsWith('.rcplugin')) {
          final rcpluginFile = File(p.join(sandboxDir.path, entryPath));
          if (await rcpluginFile.exists()) {
            final destDir = Directory(p.join(sandboxDir.path, pluginId));
            debugPrint('Migrating plugin $pluginId from .rcplugin file to directory...');
            await _extractRcPlugin(rcpluginFile, destDir);
            try {
              await rcpluginFile.delete();
            } catch (e) {
              debugPrint('Failed to delete legacy .rcplugin file: $e');
            }
          }
          entryPath = pluginId;
          // 更新数据库中的 entry_path 为 pluginId
          await db.update(
            'plugins',
            {'entry_path': pluginId},
            where: 'plugin_id = ?',
            whereArgs: [pluginId],
          );
        }

        final pluginDir = Directory(p.join(sandboxDir.path, entryPath));
        if (!await pluginDir.exists()) {
          debugPrint('Plugin directory not found: $entryPath. Cleaning DB.');
          await db.delete('plugins', where: 'plugin_id = ?', whereArgs: [pluginId]);
          continue;
        }

        PluginManifest? manifest;
        final manifestJsonStr = force ? null : row['manifest_json'] as String?;
        if (manifestJsonStr != null && manifestJsonStr.isNotEmpty) {
          try {
            manifest = PluginManifest.fromJson(
              Map<String, dynamic>.from(jsonDecode(manifestJsonStr) as Map),
            );
          } catch (e) {
            debugPrint('Failed to parse cached manifest_json for $pluginId, fallback to file: $e');
          }
        }

        if (manifest == null) {
          final manifestFile = File(p.join(pluginDir.path, 'manifest.yml'));
          if (await manifestFile.exists()) {
            final content = await manifestFile.readAsString();
            manifest = PluginManifest.fromYamlMap(loadYaml(content));
            // 缓存写回数据库
            await db.update(
              'plugins',
              {'manifest_json': jsonEncode(manifest.toJson())},
              where: 'plugin_id = ?',
              whereArgs: [pluginId],
            );
          } else {
            throw Exception('manifest.yml not found in plugin directory');
          }
        }

        loaded.add(LocalPlugin(entryPath: entryPath, manifest: manifest));

        // 确保插件的存储表存在
        if (manifest.storage.isNotEmpty) {
          await PluginStorageManager.instance.ensureTablesForPlugin(
              manifest.id, manifest.storage);
        }
      } catch (err) {
        debugPrint('Failed to load plugin ($entryPath): $err');
        await db.delete('plugins', where: 'plugin_id = ?', whereArgs: [pluginId]);
      }
    }

    _plugins = loaded;
  }

  /// 重新从磁盘读取并加载插件列表
  /// 同时扫描沙箱目录，发现未注册到数据库的新插件并自动注册
  Future<void> reloadPlugins({bool force = false}) async {
    try {
      await _scanAndRegisterNewPlugins();
      await _loadPlugins(force: force);
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

    // 扫描沙箱目录
    final entities = await sandboxDir.list().toList();
    for (final entity in entities) {
      Directory? pluginDir;
      if (entity is Directory) {
        pluginDir = entity;
      } else if (entity is Link) {
        pluginDir = Directory(entity.path);
      }

      if (pluginDir != null) {
        final pluginId = p.basename(pluginDir.path);
        if (registeredIds.contains(pluginId)) continue;

        // 发现未注册的文件夹
        final manifestFile = File(p.join(pluginDir.path, 'manifest.yml'));
        if (await manifestFile.exists()) {
          try {
            final content = await manifestFile.readAsString();
            final manifest = PluginManifest.fromYamlMap(loadYaml(content));
            await db.insert('plugins', {
              'plugin_id': manifest.id.isNotEmpty ? manifest.id : pluginId,
              'entry_path': pluginId,
              'manifest_json': jsonEncode(manifest.toJson()),
              'sort_order': nextOrder++,
            });
            debugPrint('Auto-registered plugin directory: $pluginId');
          } catch (e) {
            debugPrint('Failed to auto-register plugin directory ($pluginId): $e');
          }
        }
      } else if (entity is File && entity.path.endsWith('.rcplugin')) {
        // 发现未注册的 rcplugin 文件，将其提取并注册为目录
        final pluginId = p.basenameWithoutExtension(entity.path);
        if (registeredIds.contains(pluginId)) continue;

        try {
          final manifest = await _readManifestFromRcPlugin(entity);
          if (manifest != null) {
            final destDir = Directory(p.join(sandboxDir.path, pluginId));
            await _extractRcPlugin(entity, destDir);
            await db.insert('plugins', {
              'plugin_id': manifest.id.isNotEmpty ? manifest.id : pluginId,
              'entry_path': pluginId,
              'manifest_json': jsonEncode(manifest.toJson()),
              'sort_order': nextOrder++,
            });
            try {
              await entity.delete();
            } catch (e) {
              debugPrint('Failed to delete auto-extracted legacy .rcplugin: $e');
            }
            debugPrint('Auto-extracted and registered rcplugin: $pluginId');
          }
        } catch (e) {
          debugPrint('Failed to auto-register rcplugin ($pluginId): $e');
        }
      }
    }
  }

  Future<void> _savePlugins() async {
    final db = DatabaseManager.database;
    await db.transaction((txn) async {
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

  LocalPlugin? getPluginById(String pluginId) {
    for (final p in _plugins) {
      if (p.id == pluginId) return p;
    }
    return null;
  }

  /// 从 rcplugin 数据库文件安装插件
  Future<LocalPlugin> installPluginFromRcPlugin(
    File rcpluginFile, {
    required bool overwrite,
  }) async {
    Database? pluginDb;
    String manifestYaml;
    try {
      pluginDb = await databaseFactory.openDatabase(rcpluginFile.path, options: OpenDatabaseOptions(readOnly: true));
      final results = await pluginDb.query('metadata', columns: ['value'], where: 'key = ?', whereArgs: ['manifest_yaml']);
      if (results.isEmpty) {
        throw Exception('插件格式无效：缺少 metadata 中的 manifest_yaml');
      }
      manifestYaml = results.first['value'] as String;
    } finally {
      if (pluginDb != null) {
        await pluginDb.close();
      }
    }

    final manifest = PluginManifest.fromYamlMap(loadYaml(manifestYaml));
    final pluginId = manifest.id;

    final existingPlugin = getPluginById(pluginId);
    if (existingPlugin != null) {
      if (!overwrite) {
        throw Exception('插件已存在：$pluginId');
      }

      await _deletePluginFiles(pluginId);
      _plugins.removeWhere((p) => p.id == pluginId);
    }

    final destDir = Directory(p.join(sandboxDir.path, pluginId));
    if (await destDir.exists()) {
      await destDir.delete(recursive: true);
    }
    await _extractRcPlugin(rcpluginFile, destDir);

    final newPlugin = LocalPlugin(
      entryPath: pluginId,
      manifest: manifest,
    );

    _plugins.add(newPlugin);
    await _savePlugins();

    if (manifest.storage.isNotEmpty) {
      await PluginStorageManager.instance.ensureTablesForPlugin(
          manifest.id, manifest.storage);
    }

    notifyListeners();
    return newPlugin;
  }

  /// 重新读取单个插件的 manifest.yml（发布模式热更新）
  Future<LocalPlugin?> reloadPlugin(String pluginId) async {
    final idx = _plugins.indexWhere((p) => p.id == pluginId);
    if (idx == -1) return null;

    if (onBeforePluginFileChange != null) {
      await onBeforePluginFileChange!(pluginId);
    }

    final oldPlugin = _plugins[idx];
    final manifestFile = File(p.join(sandboxDir.path, oldPlugin.entryPath, 'manifest.yml'));
    if (!await manifestFile.exists()) {
      throw Exception('manifest.yml 不存在，无法热更新');
    }

    final content = await manifestFile.readAsString();
    final manifest = PluginManifest.fromYamlMap(loadYaml(content));

    final updatedPlugin = LocalPlugin(
      entryPath: oldPlugin.entryPath,
      manifest: manifest,
    );

    _plugins[idx] = updatedPlugin;
    await _savePlugins();

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
      allowedExtensions: ['rcplugin'],
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    final rcpluginFile = File(result.files.single.path!);

    if (onConflict != null) {
      final manifest = await _readManifestFromRcPlugin(rcpluginFile);
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

    await installPluginFromRcPlugin(rcpluginFile, overwrite: true);
  }

  /// 从 rcplugin 文件中读取 manifest.yml
  Future<PluginManifest?> _readManifestFromRcPlugin(File rcpluginFile) async {
    Database? pluginDb;
    try {
      pluginDb = await databaseFactory.openDatabase(rcpluginFile.path, options: OpenDatabaseOptions(readOnly: true));
      final results = await pluginDb.query('metadata', columns: ['value'], where: 'key = ?', whereArgs: ['manifest_yaml']);
      if (results.isEmpty) {
        return null;
      }
      final manifestYaml = results.first['value'] as String;
      return PluginManifest.fromYamlMap(loadYaml(manifestYaml));
    } catch (_) {
      return null;
    } finally {
      if (pluginDb != null) {
        await pluginDb.close();
      }
    }
  }

  bool get _isSandboxDirReady {
    try {
      return sandboxDir.path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> reorderPlugins(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 || oldIndex >= _plugins.length ||
        newIndex < 0 || newIndex >= _plugins.length) return;
    final item = _plugins.removeAt(oldIndex);
    _plugins.insert(newIndex, item);
    await _savePlugins();
    notifyListeners();
  }

  Future<void> _deletePluginFiles(String pluginId) async {
    if (onBeforePluginFileChange != null) {
      await onBeforePluginFileChange!(pluginId);
    }
    final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
    }
    final rcpluginFile = File(p.join(sandboxDir.path, '$pluginId.rcplugin'));
    if (await rcpluginFile.exists()) {
      await rcpluginFile.delete();
    }
  }

  /// 提取 rcplugin 中的所有资源到物理文件夹
  Future<void> _extractRcPlugin(File rcpluginFile, Directory destDir) async {
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    Database? pluginDb;
    try {
      pluginDb = await databaseFactory.openDatabase(rcpluginFile.path, options: OpenDatabaseOptions(readOnly: true));
      final rows = await pluginDb.query('sqlar', columns: ['name', 'sz', 'data']);
      for (final row in rows) {
        final name = row['name'] as String;
        final sz = row['sz'] as int;
        final data = row['data'] as Uint8List?;

        final cleanFilePath = p.normalize(name).replaceAll('\\', '/');
        if (cleanFilePath.startsWith('../') || cleanFilePath == '..') {
          continue;
        }

        final file = File(p.join(destDir.path, cleanFilePath));
        if (sz == 0 && data == null) {
          await Directory(file.path).create(recursive: true);
          continue;
        }

        await file.parent.create(recursive: true);

        if (data != null) {
          Uint8List contentBytes;
          if (sz > data.length) {
            contentBytes = Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
          } else {
            contentBytes = data;
          }
          await file.writeAsBytes(contentBytes);
        }
      }
    } finally {
      if (pluginDb != null) {
        await pluginDb.close();
      }
    }
  }

  Future<void> uninstallPlugin(String pluginId) async {
    await _deletePluginFiles(pluginId);
    await PluginStorageManager.instance.dropTablesForPlugin(pluginId);

    // 清理专属存储物理目录
    try {
      final supportDir = await getApplicationSupportDirectory();
      final personalStorageDir = Directory(p.join(supportDir.path, 'RainCurtainPersonalStorage', pluginId));
      if (await personalStorageDir.exists()) {
        await personalStorageDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to delete personal storage directory for $pluginId on uninstall: $e');
    }

    _plugins.removeWhere((p) => p.id == pluginId);
    await _savePlugins();
    notifyListeners();
  }
}