import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_manager.dart';
import '../../models/tab_manager.dart';
import '../../models/market_plugin.dart';
import '../../widgets/plugin_icon_widget.dart';
import 'market_plugin_icon.dart';

class MarketPluginCard extends StatelessWidget {
  final LocalPlugin? localPlugin;
  final MarketPlugin? marketPlugin;
  final bool isDesktop;
  
  // 动作回调
  final void Function(LocalPlugin plugin)? onUninstall;
  final void Function(MarketPlugin plugin)? onInstall;
  final void Function(MarketPlugin plugin)? onDetail;
  final void Function(MarketPlugin plugin)? onHistory;
  
  // 下载状态
  final bool isDownloading;
  final double downloadProgress;

  const MarketPluginCard({
    super.key,
    this.localPlugin,
    this.marketPlugin,
    required this.isDesktop,
    this.onUninstall,
    this.onInstall,
    this.onDetail,
    this.onHistory,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
  });

  bool get isOnline => marketPlugin != null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isOnline) {
      final plugin = marketPlugin!;
      final local = Provider.of<PluginManager>(context).getPluginById(plugin.pluginId);
      final displayName = plugin.name.isNotEmpty ? plugin.name : plugin.pluginId;
      final displayDesc = plugin.description.isNotEmpty ? plugin.description : '暂无功能描述';
      final displayIcon = plugin.icon;
      final displayTags = plugin.tags;

      Widget buildActionWidget() {
        if (isDownloading) {
          return SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: downloadProgress > 0 ? downloadProgress : null,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        } else if (local == null) {
          return SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              icon: Icon(Icons.download, size: 14, color: colorScheme.primary),
              padding: EdgeInsets.zero,
              onPressed: () => onInstall?.call(plugin),
              tooltip: '安装',
            ),
          );
        } else if (local.version != plugin.version) {
          return SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              icon: Icon(Icons.system_update_alt, size: 14, color: colorScheme.secondary),
              padding: EdgeInsets.zero,
              onPressed: () => onInstall?.call(plugin),
              tooltip: '更新',
            ),
          );
        } else {
          return const SizedBox(
            width: 24,
            height: 24,
            child: Icon(Icons.check, size: 14, color: Colors.green),
          );
        }
      }

      if (isDesktop) {
        // ── 在线 + 桌面 ──
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: isDownloading ? null : () => onDetail?.call(plugin),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarketPluginIconWidget(
                              iconString: displayIcon, name: displayName),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayDesc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (displayTags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: displayTags
                              .take(3)
                              .map((t) => _buildTagBadge(context, t, colorScheme))
                              .toList(),
                        ),
                      ],
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'v${plugin.version}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                              height: 1.0,
                            ),
                          ),
                          if (isDownloading)
                            Text(
                              '下载中: ${(downloadProgress * 100).toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildActionWidget(),
                      const SizedBox(width: 2),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          icon: const Icon(Icons.history, size: 14),
                          color: colorScheme.onSurfaceVariant,
                          padding: EdgeInsets.zero,
                          onPressed: () => onHistory?.call(plugin),
                          tooltip: '历史版本',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // ── 在线 + 移动端 ──
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: isDownloading ? null : () => onDetail?.call(plugin),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  MarketPluginIconWidget(
                      iconString: displayIcon, name: displayName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayDesc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                        if (displayTags.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: displayTags
                                .take(2)
                                .map((t) => _buildTagBadge(context, t, colorScheme))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildActionWidget(),
                      const SizedBox(width: 2),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: IconButton(
                          icon: const Icon(Icons.history, size: 14),
                          color: colorScheme.onSurfaceVariant,
                          padding: EdgeInsets.zero,
                          onPressed: () => onHistory?.call(plugin),
                          tooltip: '历史版本',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } else {
      // ── 已安装插件卡片 ──
      final plugin = localPlugin!;

      if (isDesktop) {
        // ── 已安装 + 桌面端 ──
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: () {
              Provider.of<TabManager>(context, listen: false)
                  .openOrSwitchTab(plugin);
            },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PluginIconWidget(plugin: plugin),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plugin.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  plugin.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (plugin.manifest.tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: plugin.manifest.tags
                              .take(3)
                              .map((t) => _buildTagBadge(context, t, colorScheme))
                              .toList(),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        'v${plugin.version} · ${plugin.author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      color: colorScheme.onSurfaceVariant,
                      padding: EdgeInsets.zero,
                      onPressed: () => onUninstall?.call(plugin),
                      tooltip: '卸载',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // ── 已安装 + 移动端 ──
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: InkWell(
            onTap: () {
              Provider.of<TabManager>(context, listen: false)
                  .openOrSwitchTab(plugin);
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PluginIconWidget(plugin: plugin),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          plugin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plugin.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                        if (plugin.manifest.tags.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: plugin.manifest.tags
                                .take(2)
                                .map((t) => _buildTagBadge(context, t, colorScheme))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      color: colorScheme.onSurfaceVariant,
                      padding: EdgeInsets.zero,
                      onPressed: () => onUninstall?.call(plugin),
                      tooltip: '卸载',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _buildTagBadge(BuildContext context, String tag, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
