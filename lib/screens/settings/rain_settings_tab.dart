import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../models/s3_config_manager.dart';
import '../../models/update_manager.dart';
import '../../widgets/update_dialog.dart';

/// 雨幕设置选项卡
class RainSettingsTab extends StatefulWidget {
  const RainSettingsTab({super.key});

  @override
  State<RainSettingsTab> createState() => _RainSettingsTabState();
}

class _RainSettingsTabState extends State<RainSettingsTab> {
  final TextEditingController _angleController = TextEditingController();
  final GlobalKey _directionPickerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _angleController.text = themeProvider.rainAngle.round().toString();
    themeProvider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.removeListener(_onThemeChanged);
    _angleController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _angleController.text = themeProvider.rainAngle.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Row(
                      children: [
                        Icon(
                          Icons.water_drop_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '雨滴效果',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 雨滴开关
                    _buildRainToggle(context, themeProvider),

                    // 方向控制（仅在开启时显示）
                    if (themeProvider.showRain) ...[
                      const SizedBox(height: 20),
                      _buildRainAngleControl(context, themeProvider),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildVersionCard(context),
      ],
    );
  }

  Widget _buildRainToggle(BuildContext context, ThemeProvider themeProvider) {
    return SwitchListTile(
      value: themeProvider.showRain,
      onChanged: (value) => themeProvider.setShowRain(value),
      title: const Text('显示雨滴动画', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        themeProvider.showRain ? '雨滴效果已开启' : '雨滴效果已关闭',
        style: const TextStyle(fontSize: 12),
      ),
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      secondary: Icon(
        themeProvider.showRain
            ? Icons.water_drop
            : Icons.water_drop_outlined,
        size: 20,
        color: themeProvider.showRain
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    );
  }

  Widget _buildRainAngleControl(
      BuildContext context, ThemeProvider themeProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('雨滴方向', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '调整雨滴下落的角度',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildDirectionPicker(context, themeProvider),
            const SizedBox(width: 24),
            Expanded(child: _buildAngleInput(context, themeProvider)),
          ],
        ),
      ],
    );
  }

  Widget _buildDirectionPicker(
      BuildContext context, ThemeProvider themeProvider) {
    return Container(
      key: _directionPickerKey,
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 2,
        ),
        gradient: RadialGradient(
          colors: [
            Theme.of(context).colorScheme.surfaceContainerHighest,
            Theme.of(context).colorScheme.surface,
          ],
          radius: 0.8,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            _updateAngleFromGlobalPosition(details.globalPosition),
        onPanUpdate: (details) =>
            _updateAngleFromGlobalPosition(details.globalPosition),
        child: CustomPaint(
          painter: _DirectionPainter(
            angle: themeProvider.rainAngle,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _updateAngleFromGlobalPosition(Offset globalPosition) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final renderBox =
        _directionPickerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(globalPosition);
    final center = Offset(
      renderBox.size.width / 2,
      renderBox.size.height / 2,
    );

    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    var newAngle = math.atan2(dy, dx) * 180 / math.pi + 90;

    if (newAngle < 0) newAngle += 360;
    if (newAngle > 360) newAngle -= 360;

    themeProvider.setRainAngle(newAngle);
    _angleController.text = newAngle.round().toString();
  }

  Widget _buildAngleInput(BuildContext context, ThemeProvider themeProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('角度值', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: _angleController,
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: false,
          ),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '角度 (-360 ~ 360)',
            suffixText: '°',
          ),
          onSubmitted: (value) {
            final angle = double.tryParse(value);
            if (angle != null) {
              themeProvider.setRainAngle(angle);
            } else {
              _angleController.text = themeProvider.rainAngle.round().toString();
            }
          },
        ),
      ],
    );
  }

  Widget _buildVersionCard(BuildContext context) {
    return Card(
      child: Consumer<UpdateManager>(
        builder: (context, updateManager, _) {
          final (localVer, localBuild) = updateManager.getLocalVersionInfo();
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          // 根据当前状态显示不同的状态文案和图标/徽章
          Widget trailingWidget;
          Widget? subtitleWidget;
          
          switch (updateManager.status) {
            case UpdateStatus.checking:
              trailingWidget = const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
              subtitleWidget = Text(
                '正在检查更新...',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              );
              break;
            case UpdateStatus.hasUpdate:
              trailingWidget = Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 14,
                      color: colorScheme.onPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '可更新',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              );
              subtitleWidget = Text(
                '发现新版本: v${updateManager.latestVersion} (${updateManager.latestBuildNumber})',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              );
              break;
            case UpdateStatus.downloading:
              trailingWidget = SizedBox(
                width: 80,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: updateManager.downloadProgress,
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(updateManager.downloadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
              subtitleWidget = Text(
                '正在下载更新包...',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              );
              break;
            case UpdateStatus.downloaded:
              trailingWidget = Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '已下载',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              );
              subtitleWidget = Text(
                '更新已就绪，请点击安装',
                style: TextStyle(fontSize: 12, color: colorScheme.primary),
              );
              break;
            case UpdateStatus.error:
              trailingWidget = Icon(
                Icons.error_outline,
                color: colorScheme.error,
              );
              subtitleWidget = Text(
                updateManager.errorMessage ?? '检查更新失败',
                style: TextStyle(fontSize: 12, color: colorScheme.error),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              break;
            case UpdateStatus.noUpdate:
              trailingWidget = Icon(
                Icons.check,
                color: colorScheme.outline,
              );
              subtitleWidget = Text(
                '当前已是最新版本',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              );
              break;
            case UpdateStatus.idle:
              trailingWidget = Icon(
                Icons.chevron_right,
                color: colorScheme.outline,
              );
              subtitleWidget = Text(
                '点击版本号检查更新',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              );
              break;
          }

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _handleUpdateCheck(context, updateManager),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '关于与更新',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '当前版本: v$localVer ($localBuild)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: subtitleWidget,
                    trailing: trailingWidget,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleUpdateCheck(BuildContext context, UpdateManager updateManager) async {
    final configManager = Provider.of<S3ConfigManager>(context, listen: false);
    final config = configManager.config;
    
    // 如果已经在下载、已下载、出错或是有更新，点击则直接弹出对话框
    if (updateManager.status == UpdateStatus.downloading ||
        updateManager.status == UpdateStatus.downloaded ||
        updateManager.status == UpdateStatus.error ||
        updateManager.status == UpdateStatus.hasUpdate) {
      if (config != null) {
        showUpdateDialog(context, updateManager, config);
      }
      return;
    }

    if (config == null || config.publicUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置更新源（S3/R2 配置无效或缺失）')),
      );
      return;
    }

    // 触发检查更新
    await updateManager.checkForUpdates(config);

    if (!mounted) return;

    if (updateManager.status == UpdateStatus.hasUpdate) {
      showUpdateDialog(context, updateManager, config);
    } else if (updateManager.status == UpdateStatus.noUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本')),
      );
    } else if (updateManager.status == UpdateStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(updateManager.errorMessage ?? '检查更新失败')),
      );
    }
  }
}

/// 方向选择器绘制器
class _DirectionPainter extends CustomPainter {
  final double angle;
  final Color color;

  _DirectionPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // 绘制中心点
    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 6, centerPaint);

    // 计算箭头终点
    final radians = (angle - 90) * math.pi / 180;
    final arrowEnd = Offset(
      center.dx + radius * 0.8 * math.cos(radians),
      center.dy + radius * 0.8 * math.sin(radians),
    );

    // 绘制指示线
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, arrowEnd, linePaint);

    // 绘制箭头
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const arrowHeadAngle = math.pi / 6;
    const arrowHeadLength = 16.0;

    final p1 = Offset(
      arrowEnd.dx - arrowHeadLength * math.cos(radians - arrowHeadAngle),
      arrowEnd.dy - arrowHeadLength * math.sin(radians - arrowHeadAngle),
    );
    final p2 = Offset(
      arrowEnd.dx - arrowHeadLength * math.cos(radians + arrowHeadAngle),
      arrowEnd.dy - arrowHeadLength * math.sin(radians + arrowHeadAngle),
    );

    final path = Path()
      ..moveTo(arrowEnd.dx, arrowEnd.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(_DirectionPainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.color != color;
  }
}
