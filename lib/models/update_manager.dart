import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../plugin_api_server.dart';
import '../utils/s3_client.dart';
import 's3_config_manager.dart';

/// 自动更新检查状态枚举
enum UpdateStatus {
  idle,          // 闲置
  checking,      // 正在检查
  hasUpdate,     // 发现新版本
  noUpdate,      // 已是最新版本
  error,         // 检查/下载失败
  downloading,   // 正在下载
  downloaded,    // 下载完成
}

/// 自动更新管理器
/// 负责从 S3 桶拉取 `update.json`，比对版本信息，并在本地异步下载和触发安装更新。
class UpdateManager extends ChangeNotifier {
  UpdateStatus _status = UpdateStatus.idle;
  String? _errorMessage;
  
  String? _latestVersion;
  int? _latestBuildNumber;
  String? _changelog;
  String? _releaseDate;
  
  String? _remoteWinFile;
  String? _remoteAndroidFile;

  double _downloadProgress = 0.0;
  String? _localDownloadPath;

  UpdateStatus get status => _status;
  String? get errorMessage => _errorMessage;
  
  String? get latestVersion => _latestVersion;
  int? get latestBuildNumber => _latestBuildNumber;
  String? get changelog => _changelog;
  String? get releaseDate => _releaseDate;
  
  double get downloadProgress => _downloadProgress;
  String? get localDownloadPath => _localDownloadPath;

  /// 解析当前本地版本信息
  (String version, int buildNumber) getLocalVersionInfo() {
    final fullVer = PluginApiServer.kAppVersion; // 例如 "1.1.9+2"
    final parts = fullVer.split('+');
    final version = parts[0];
    final buildNumber = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
    return (version, buildNumber);
  }

  /// 检查更新
  Future<void> checkForUpdates(S3Config config) async {
    if (_status == UpdateStatus.checking || _status == UpdateStatus.downloading) return;

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final client = S3Client(publicUrl: config.publicUrl);

      // 1. 读取 update.json
      final jsonStr = await client.readObject('update.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      _latestVersion = data['version']?.toString();
      _latestBuildNumber = int.tryParse(data['buildNumber']?.toString() ?? '1') ?? 1;
      _changelog = data['changelog']?.toString() ?? '无更新说明';
      _releaseDate = data['releaseDate']?.toString();
      _remoteWinFile = data['windowsUrl']?.toString();
      _remoteAndroidFile = data['androidUrl']?.toString();

      if (_latestVersion == null) {
        throw const FormatException('远程配置文件中缺少 version 字段');
      }

      // 2. 比对版本
      final (localVer, localBuild) = getLocalVersionInfo();
      final hasNew = _hasNewVersion(
        localVer: localVer,
        remoteVer: _latestVersion!,
        localBuild: localBuild,
        remoteBuild: _latestBuildNumber!,
      );

      if (hasNew) {
        _status = UpdateStatus.hasUpdate;
        debugPrint('[UpdateManager] 发现新版本: $_latestVersion+$_latestBuildNumber');
      } else {
        _status = UpdateStatus.noUpdate;
        debugPrint('[UpdateManager] 当前已是最新版本');
      }
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = '检查更新失败: $e';
      debugPrint('[UpdateManager] 检查更新出错: $e');
    } finally {
      notifyListeners();
    }
  }

  /// 下载当前平台的更新包
  Future<void> downloadUpdate(S3Config config) async {
    if (_status != UpdateStatus.hasUpdate && _status != UpdateStatus.error) return;

    final String? remoteFile = Platform.isWindows ? _remoteWinFile : _remoteAndroidFile;
    if (remoteFile == null || remoteFile.isEmpty) {
      _status = UpdateStatus.error;
      _errorMessage = '未找到适配当前平台的远程安装包路径';
      notifyListeners();
      return;
    }

    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      final client = S3Client(publicUrl: config.publicUrl);

      // 获取本地临时存储路径
      final tempDir = await getTemporaryDirectory();
      final filename = p.basename(remoteFile);
      final savePath = p.join(tempDir.path, 'RainCurtain-Update', filename);

      // 执行下载并监听进度
      await client.downloadObject(
        remoteFile,
        savePath,
        onProgress: (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      _localDownloadPath = savePath;
      _status = UpdateStatus.downloaded;
      debugPrint('[UpdateManager] 更新包下载完成，保存在: $savePath');
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = '下载安装包失败: $e';
      debugPrint('[UpdateManager] 下载安装包出错: $e');
    } finally {
      notifyListeners();
    }
  }

  /// 重置状态至闲置，可重新检查更新
  void resetStatus() {
    _status = UpdateStatus.idle;
    _errorMessage = null;
    _downloadProgress = 0.0;
    _localDownloadPath = null;
    notifyListeners();
  }

  /// 触发运行安装程序
  Future<void> installUpdate() async {
    if (_status != UpdateStatus.downloaded || _localDownloadPath == null) return;

    try {
      if (Platform.isWindows) {
        // Windows：运行外部 EXE 独立安装程序，然后安全退出当前 Flutter 进程
        await Process.start(_localDownloadPath!, [], runInShell: true);
        exit(0);
      } else if (Platform.isAndroid) {
        // Android：先确认「安装未知来源应用」权限
        final canInstall = await Permission.requestInstallPackages.status;
        if (!canInstall.isGranted) {
          final result = await Permission.requestInstallPackages.request();
          if (!result.isGranted) {
            // 用户拒绝权限——引导去设置
            debugPrint('[UpdateManager] 「安装未知来源应用」权限被拒绝，将引导用户开启权限');
            await openAppSettings();
            // 设置错误状态提示用户需要手动开启权限后再点重试
            _status = UpdateStatus.error;
            _errorMessage = '安装需要「安装未知来源应用」权限。\n请在系统设置中开启权限后，返回应用点击重试。';
            notifyListeners();
            return;
          }
        }

        // 权限已授予，调用系统安装器打开 APK
        debugPrint('[UpdateManager] 正在调起 APK 安装器：$_localDownloadPath');
        final openResult = await OpenFile.open(
          _localDownloadPath!,
          type: 'application/vnd.android.package-archive',
        );
        if (openResult.type != ResultType.done) {
          _status = UpdateStatus.error;
          _errorMessage = 'APK 安装器启动失败：${openResult.message}';
          notifyListeners();
        }
      } else {
        debugPrint('[UpdateManager] 暂不支持当前平台的自动安装');
      }
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = '启动安装程序失败: $e';
      notifyListeners();
    }
  }

  /// 版本对比核心算法
  bool _hasNewVersion({
    required String localVer,
    required String remoteVer,
    required int localBuild,
    required int remoteBuild,
  }) {
    final localParts = localVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final remoteParts = remoteVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final localVal = i < localParts.length ? localParts[i] : 0;
      final remoteVal = i < remoteParts.length ? remoteParts[i] : 0;
      if (remoteVal > localVal) return true;
      if (remoteVal < localVal) return false;
    }

    // 主版本号完全一致时，比较 Build Number (构建号)
    return remoteBuild > localBuild;
  }
}
