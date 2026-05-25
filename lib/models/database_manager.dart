import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'plugin_storage_manager.dart';

/// 数据库管理器
/// 单例模式管理 SQLite 数据库实例，负责建表、版本迁移、旧数据迁移
class DatabaseManager {
  static DatabaseManager? _instance;
  static Database? _database;

  DatabaseManager._();

  static DatabaseManager get instance {
    _instance ??= DatabaseManager._();
    return _instance!;
  }

  /// 获取已初始化的 Database 实例
  static Database get database {
    if (_database == null) {
      throw StateError('DatabaseManager has not been initialized. '
          'Call DatabaseManager.instance.init() first.');
    }
    return _database!;
  }

  /// 数据库文件所在目录
  late final String dbDirectoryPath;

  /// 数据库文件完整路径
  late final String dbPath;

  /// 初始化数据库
  /// 必须在 WidgetsFlutterBinding.ensureInitialized() 之后调用
  Future<void> init() async {
    if (_database != null) return;

    // 初始化 FFI（Android / Windows 统一入口）
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final supportDir = await getApplicationSupportDirectory();
    dbDirectoryPath = p.join(supportDir.path, 'RainCurtain');
    final dbDir = Directory(dbDirectoryPath);
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    dbPath = p.join(dbDirectoryPath, 'raincurtain.db');

    _database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    debugPrint('DatabaseManager initialized at: $dbPath');

    // 初始化 PluginStorageManager 单例
    PluginStorageManager.init(_database!);

    // 执行旧数据迁移
    await _migrateOldData(supportDir);
  }

  /// 建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pool_variables (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pool_id TEXT NOT NULL,
        variable_name TEXT NOT NULL,
        type TEXT NOT NULL,
        value TEXT,
        source_plugin_id TEXT,
        updated_at TEXT NOT NULL,
        UNIQUE(pool_id, variable_name)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_pool_variables_pool ON pool_variables(pool_id)');
    await db.execute(
        'CREATE INDEX idx_pool_variables_source ON pool_variables(pool_id, source_plugin_id)');

    await db.execute('''
      CREATE TABLE plugins (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plugin_id TEXT NOT NULL UNIQUE,
        entry_path TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');

    debugPrint('Database tables created (version $version)');
  }

  /// 版本升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Database upgrade: $oldVersion → $newVersion');

    if (oldVersion < 2) {
      // v1 → v2：删除旧的共享 local_storage 表
      // 旧数据无法自动映射到新的结构化表（schema 完全不同）
      await db.execute('DROP TABLE IF EXISTS local_storage');
      debugPrint('Dropped legacy local_storage table');
    }

    if (oldVersion < 3) {
      // v2 → v3：plugins 表添加 sort_order 列，用于手动排序
      await db.execute(
          'ALTER TABLE plugins ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
      // 根据现有主键 id 赋初始排序值，保持原始插入顺序
      await db.execute('UPDATE plugins SET sort_order = id');
      debugPrint('Added sort_order column to plugins table');
    }
  }

  /// 旧数据迁移
  /// 检测并迁移 JSON 文件中的旧数据
  Future<void> _migrateOldData(Directory supportDir) async {
    try {
      bool anyMigrated = false;

      // 1. 清理旧的 LocalStorage JSON 文件目录（数据无法自动迁移到新结构化表）
      final localStorageDir = Directory(
          p.join(supportDir.path, 'RainCurtainPluginsData', 'localstorage'));
      if (await localStorageDir.exists()) {
        try {
          await localStorageDir.delete(recursive: true);
          debugPrint('Old localstorage directory deleted (data not migrated)');
          anyMigrated = true;
        } catch (e) {
          debugPrint('Failed to delete old localstorage directory: $e');
        }
      }

      // 2. 迁移 VariablePool JSON 文件
      final poolsDir =
          Directory(p.join(supportDir.path, 'RainCurtainPoolsData'));
      if (await poolsDir.exists()) {
        final migrated = await _migratePoolVariableFiles(poolsDir);
        if (migrated) {
          anyMigrated = true;
          try {
            await poolsDir.delete(recursive: true);
            debugPrint('Old pools data directory deleted');
          } catch (e) {
            debugPrint('Failed to delete old pools data directory: $e');
          }
        }
      }

      if (anyMigrated) {
        debugPrint('Old data migration completed');
      }
    } catch (e, stackTrace) {
      debugPrint('Data migration failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// 迁移 VariablePool JSON 文件到数据库
  Future<bool> _migratePoolVariableFiles(Directory poolsDir) async {
    bool migrated = false;
    final db = _database!;

    try {
      final poolDirs = await poolsDir.list().toList();
      for (final poolEntity in poolDirs) {
        if (poolEntity is Directory) {
          final poolId = p.basename(poolEntity.path);
          // 用于 last-write-wins 合并
          final Map<String, Map<String, dynamic>> merged = {};

          final files = await poolEntity.list().toList();
          for (final fileEntity in files) {
            if (fileEntity is File && fileEntity.path.endsWith('.json')) {
              try {
                final pluginId =
                    p.basenameWithoutExtension(fileEntity.path);
                final content = await fileEntity.readAsString();
                final jsonData =
                    jsonDecode(content) as Map<String, dynamic>;
                final data =
                    jsonData['data'] as Map<String, dynamic>? ?? {};

                for (final entry in data.entries) {
                  final varData =
                      Map<String, dynamic>.from(entry.value as Map);
                  final updatedAt =
                      DateTime.parse(varData['updatedAt'] as String);

                  if (!merged.containsKey(entry.key)) {
                    varData['_sourcePluginId'] = pluginId;
                    merged[entry.key] = varData;
                  } else {
                    final existingUpdatedAt = DateTime.parse(
                        merged[entry.key]!['updatedAt'] as String);
                    if (updatedAt.isAfter(existingUpdatedAt)) {
                      varData['_sourcePluginId'] = pluginId;
                      merged[entry.key] = varData;
                    }
                  }
                }
              } catch (e) {
                debugPrint(
                    'Failed to migrate pool variable file ${fileEntity.path}: $e');
              }
            }
          }

          if (merged.isNotEmpty) {
            final batch = db.batch();
            for (final entry in merged.entries) {
              final varData = entry.value;
              final value = varData['value'];
              batch.insert(
                'pool_variables',
                {
                  'pool_id': poolId,
                  'variable_name': varData['name'] as String,
                  'type': varData['type'] as String,
                  'value': value != null ? jsonEncode(value) : null,
                  'source_plugin_id':
                      varData['_sourcePluginId'] as String? ??
                          varData['sourcePluginId'] as String?,
                  'updated_at': varData['updatedAt'] as String,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await batch.commit(noResult: true);
            migrated = true;
            debugPrint(
                'Migrated pool variables for pool: $poolId (${merged.length} variables)');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to migrate pool variables: $e');
    }

    return migrated;
  }

  /// 关闭数据库
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
