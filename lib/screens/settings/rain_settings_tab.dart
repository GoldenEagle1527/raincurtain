import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';

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
