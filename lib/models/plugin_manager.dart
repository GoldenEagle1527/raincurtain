import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'plugin_manifest.dart';
import 'plugin_icon.dart';

class PluginUpgradeInfo {
  final String existingId;
  final String existingVersion;
  final PluginManifest newManifest;
  final File zipFile;
  final VersionComparisonResult versionResult;

  PluginUpgradeInfo({
    required this.existingId,
    required this.existingVersion,
    required this.newManifest,
    required this.zipFile,
    required this.versionResult,
  });
}

class LocalPlugin {
  final String id;
  final String entryPath;
  final PluginManifest manifest;

  const LocalPlugin({
    required this.id,
    required this.entryPath,
    required this.manifest,
  });

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
    'id': id,
    'entryPath': entryPath,
    'manifest': manifest.toJson(),
  };

  factory LocalPlugin.fromJson(Map<String, dynamic> json) {
    final manifestJson = json['manifest'];

    if (manifestJson is Map) {
      return LocalPlugin(
        id: json['id'],
        entryPath: json['entryPath'],
        manifest: PluginManifest.fromJson(
          Map<String, dynamic>.from(manifestJson),
        ),
      );
    }

    return LocalPlugin(
      id: (json['id'] ?? '').toString(),
      entryPath: (json['entryPath'] ?? '').toString(),
      manifest: PluginManifest(
        name: (json['name'] ?? '未知插件').toString(),
        description: '旧版插件数据，缺少 manifest.yml 描述信息',
        version: '0.0.0',
        author: 'Unknown',
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
    final prefs = await SharedPreferences.getInstance();
    final pluginsJson = prefs.getString('saved_plugins');
    if (pluginsJson != null) {
      final List<dynamic> decoded = jsonDecode(pluginsJson);
      _plugins = decoded.map((e) => LocalPlugin.fromJson(e)).toList();
    }
  }

  Future<void> _savePlugins() async {
    final prefs = await SharedPreferences.getInstance();
    final pluginsJson = jsonEncode(_plugins.map((e) => e.toJson()).toList());
    await prefs.setString('saved_plugins', pluginsJson);
  }

  Future<void> installPlugin() async {
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

    final pluginId = _uuid.v7();
    final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
    await pluginDir.create(recursive: true);

    try {
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(pluginDir.path, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory(p.join(pluginDir.path, filename)).create(recursive: true);
        }
      }

      final manifestFile = await _findManifestFile(pluginDir);
      if (manifestFile == null) {
        throw Exception('插件格式无效：缺少 manifest.yml 文件');
      }

      final manifest = await _readManifest(manifestFile);
      final entryPath = await _findEntryPath(pluginDir, pluginId);

      final newPlugin = LocalPlugin(
        id: pluginId,
        entryPath: entryPath,
        manifest: manifest,
      );

      _plugins.add(newPlugin);
      await _savePlugins();
      notifyListeners();
    } catch (_) {
      if (await pluginDir.exists()) {
        await pluginDir.delete(recursive: true);
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

  Future<void> uninstallPlugin(String pluginId) async {
    final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
    }
    _plugins.removeWhere((p) => p.id == pluginId);
    await _savePlugins();
    notifyListeners();
  }

  Future<PluginUpgradeInfo?> prepareUpgrade(String existingPluginId) async {
    final existingPlugin = _plugins.firstWhere((p) => p.id == existingPluginId);
    
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    final zipFile = File(result.files.single.path!);
    
    // 临时解压并解析新插件的 manifest
    final tempDir = Directory(p.join(Directory.systemTemp.path, _uuid.v7()));
    await tempDir.create(recursive: true);
    
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
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

      final newManifest = await _readManifest(manifestFile);
      
      // 验证插件名称
      if (newManifest.name != existingPlugin.name) {
        throw Exception('插件名称不匹配，无法升级');
      }

      // 比较版本
      final versionResult = existingPlugin.manifest.compareVersion(newManifest.version);

      return PluginUpgradeInfo(
        existingId: existingPluginId,
        existingVersion: existingPlugin.version,
        newManifest: newManifest,
        zipFile: zipFile,
        versionResult: versionResult,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> upgradePlugin(String pluginId, File zipFile) async {
    final pluginIndex = _plugins.indexWhere((p) => p.id == pluginId);
    if (pluginIndex == -1) {
      throw Exception('插件不存在');
    }

    final pluginDir = Directory(p.join(sandboxDir.path, pluginId));
    
    // 删除旧插件目录
    if (await pluginDir.exists()) {
      await pluginDir.delete(recursive: true);
    }

    // 解压新插件
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    await pluginDir.create(recursive: true);

    try {
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(pluginDir.path, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory(p.join(pluginDir.path, filename)).create(recursive: true);
        }
      }

      final manifestFile = await _findManifestFile(pluginDir);
      if (manifestFile == null) {
        throw Exception('插件格式无效：缺少 manifest.yml 文件');
      }

      final manifest = await _readManifest(manifestFile);
      final entryPath = await _findEntryPath(pluginDir, pluginId);

      final updatedPlugin = LocalPlugin(
        id: pluginId,
        entryPath: entryPath,
        manifest: manifest,
      );

      _plugins[pluginIndex] = updatedPlugin;
      await _savePlugins();
      notifyListeners();
    } catch (_) {
      // 如果升级失败，尝试回滚
      if (await pluginDir.exists()) {
        await pluginDir.delete(recursive: true);
      }
      rethrow;
    }
  }
}
