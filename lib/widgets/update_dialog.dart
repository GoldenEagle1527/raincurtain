import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/s3_config_manager.dart';
import '../models/update_manager.dart';

/// 弹出版本更新详细对话框
void showUpdateDialog(BuildContext context, UpdateManager updateManager, S3Config config) {
  showDialog(
    context: context,
    barrierDismissible: false, // 阻止下载中途点击背景关闭
    builder: (dialogContext) {
      return Consumer<UpdateManager>(
        builder: (context, manager, child) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          
          final isDownloading = manager.status == UpdateStatus.downloading;
          final isDownloaded = manager.status == UpdateStatus.downloaded;
          final isError = manager.status == UpdateStatus.error;

          IconData iconData;
          Color iconColor;
          String titleText;

          if (isDownloaded) {
            iconData = Icons.check_circle_rounded;
            iconColor = colorScheme.primary;
            titleText = '更新准备就绪';
          } else if (isError) {
            iconData = Icons.error_outline;
            iconColor = colorScheme.error;
            titleText = '更新失败';
          } else if (isDownloading) {
            iconData = Icons.cloud_download;
            iconColor = colorScheme.primary;
            titleText = '正在下载更新';
          } else {
            iconData = Icons.system_update_alt;
            iconColor = colorScheme.primary;
            titleText = '发现新版本可用';
          }

          Widget contentWidget;
          if (isDownloading) {
            contentWidget = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '正在下载更新包...',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    Text(
                      '${(manager.downloadProgress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: manager.downloadProgress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '请勿关闭应用，下载完成后将自动提示安装。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          } else if (isDownloaded) {
            contentWidget = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本 v${manager.latestVersion} 已下载成功。',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '请点击下方按钮重启应用以完成安装。',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          } else if (isError) {
            contentWidget = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下载过程中遇到问题：',
                  style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  manager.errorMessage ?? '网络请求超时，请稍后重试。',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          } else {
            contentWidget = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最新版本: v${manager.latestVersion} (${manager.latestBuildNumber})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (manager.releaseDate != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '发布日期: ${manager.releaseDate}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('更新日志：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      manager.changelog ?? '无详细更新说明。',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        height: 1.4,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          List<Widget> actionsList = [];
          if (isDownloading) {
            actionsList = [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            ];
          } else if (isDownloaded) {
            actionsList = [
              FilledButton(
                onPressed: () => manager.installUpdate(),
                child: const Text('重启并安装'),
              ),
            ];
          } else if (isError) {
            actionsList = [
              TextButton(
                onPressed: () {
                  manager.resetStatus();
                  Navigator.pop(dialogContext);
                },
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () => manager.downloadUpdate(config),
                child: const Text('重试'),
              ),
            ];
          } else {
            actionsList = [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () {
                  manager.downloadUpdate(config);
                },
                child: const Text('立即更新'),
              ),
            ];
          }

          return AlertDialog(
            icon: Icon(
              iconData,
              color: iconColor,
              size: 32,
            ),
            title: Text(titleText),
            content: contentWidget,
            actions: actionsList,
          );
        },
      );
    },
  );
}
