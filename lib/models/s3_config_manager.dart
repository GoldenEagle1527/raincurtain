import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自动更新配置数据类（仅包含公开的更新下载基准 URL）
class S3Config {
  final String publicUrl;

  S3Config({
    required this.publicUrl,
  });

  factory S3Config.fromJson(Map<String, dynamic> json) {
    return S3Config(
      publicUrl: json['publicUrl']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'publicUrl': publicUrl,
    };
  }
}

/// S3 配置文件管理器
/// 维护本地 `s3_config.json` 的生命周期，提供在应用中的实时配置修改与持久化。
class S3ConfigManager extends ChangeNotifier {
  S3Config? _config;
  bool _isInit = false;

  S3Config? get config => _config;
  bool get isInit => _isInit;

  /// 初始化加载配置
  /// 优先加载系统应用支持目录下的 `s3_config.json`。若不存在，则从 Assets 中读取默认配置，并存入本地。
  Future<void> init() async {
    if (_isInit) return;

    try {
      final supportDir = await getApplicationSupportDirectory();
      final configDir = Directory(p.join(supportDir.path, 'RainCurtain'));
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final configFile = File(p.join(configDir.path, 's3_config.json'));

      // 总是加载内置资产的默认配置
      final defaultContent = await rootBundle.loadString('assets/s3_config.json');
      final defaultConfig = S3Config.fromJson(jsonDecode(defaultContent));

      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final localConfig = S3Config.fromJson(jsonDecode(content));
        
        // 如果内置配置与本地缓存的公共地址不同，说明更新了资产，强制覆盖本地缓存
        if (localConfig.publicUrl != defaultConfig.publicUrl) {
          _config = defaultConfig;
          await configFile.writeAsString(jsonEncode(defaultConfig.toJson()));
          debugPrint('[S3ConfigManager] 内置 S3 配置的 publicUrl 与本地缓存不一致，已使用最新内置资产覆盖本地配置');
        } else {
          _config = localConfig;
          debugPrint('[S3ConfigManager] 已从系统数据目录成功加载 S3 配置');
        }
      } else {
        _config = defaultConfig;
        
        // 写入到本地，方便未来用户在运行期自定义修改
        await configFile.writeAsString(jsonEncode(_config!.toJson()));
        debugPrint('[S3ConfigManager] 本地配置不存在，已使用内置资产初始化本地配置');
      }
    } catch (e) {
      debugPrint('[S3ConfigManager] 初始化配置失败，错误原因: $e');
      // 兜底防崩溃配置
      _config = S3Config(
        publicUrl: '',
      );
    } finally {
      _isInit = true;
      notifyListeners();
    }
  }

  /// 更改配置并持久化写入本地磁盘
  Future<void> saveConfig(S3Config newConfig) async {
    _config = newConfig;
    notifyListeners();

    try {
      final supportDir = await getApplicationSupportDirectory();
      final configFile = File(p.join(supportDir.path, 'RainCurtain', 's3_config.json'));
      await configFile.writeAsString(jsonEncode(newConfig.toJson()));
      debugPrint('[S3ConfigManager] 新的 S3 配置文件已成功保存');
    } catch (e) {
      debugPrint('[S3ConfigManager] 保存 S3 配置文件失败: $e');
    }
  }
}
