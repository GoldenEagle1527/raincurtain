import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 雨幕背景组件
/// 提供全局雨滴动画效果
class RainBackground extends StatefulWidget {
  final Widget child;
  final Color? rainColor;
  final int dropCount;
  final double opacity;
  final bool showRain;
  final double angle;

  const RainBackground({
    super.key,
    required this.child,
    this.rainColor,
    this.dropCount = 80,
    this.opacity = 0.25,
    this.showRain = true,
    this.angle = 145,
  });

  @override
  State<RainBackground> createState() => _RainBackgroundState();
}

class _RainBackgroundState extends State<RainBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<_RainDrop> _drops;
  final Random _random = Random();
  double _elapsedSeconds = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _drops = List.generate(
      widget.dropCount,
      (i) => _RainDrop.random(_random),
    );
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
    });
  }

  @override
  void didUpdateWidget(RainBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dropCount != widget.dropCount) {
      _drops = List.generate(
        widget.dropCount,
        (i) => _RainDrop.random(_random),
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.rainColor ?? Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        widget.child,
        if (widget.showRain)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RainPainter(
                  drops: _drops,
                  elapsedSeconds: _elapsedSeconds,
                  color: color,
                  opacity: widget.opacity,
                  angle: widget.angle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 雨滴数据模型
class _RainDrop {
  final double x;
  final double speed;
  final double size;
  final double tailLength;
  final double offset;

  const _RainDrop({
    required this.x,
    required this.speed,
    required this.size,
    required this.tailLength,
    required this.offset,
  });

  factory _RainDrop.random(Random random) {
    return _RainDrop(
      x: random.nextDouble(),
      speed: 0.3 + random.nextDouble() * 0.5,
      size: 1.5 + random.nextDouble() * 2.0,
      tailLength: 1.0 + random.nextDouble() * 3.0,
      offset: random.nextDouble(),
    );
  }
}

/// 雨滴绘制器
class _RainPainter extends CustomPainter {
  final List<_RainDrop> drops;
  final double elapsedSeconds;
  final Color color;
  final double opacity;
  final double angle;

  static const double _baseCycleDuration = 4.0;

  _RainPainter({
    required this.drops,
    required this.elapsedSeconds,
    required this.color,
    required this.opacity,
    required this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 将用户角度转换为绘制弧度
    final radians = (angle - 90) * pi / 180;
    final dx = cos(radians);
    final dy = sin(radians);

    // 垂直于运动方向的单位向量
    final perpX = -dy;
    final perpY = dx;

    // 计算对角线长度
    final diag = sqrt(size.width * size.width + size.height * size.height);

    for (final drop in drops) {
      // 计算当前雨滴的周期进度
      final cycleDuration = _baseCycleDuration / drop.speed;
      final double t = ((elapsedSeconds / cycleDuration) + drop.offset) % 1.0;

      // 计算透明度（淡入淡出）
      double alpha = opacity;
      if (t < 0.1) {
        alpha = opacity * (t / 0.1);
      } else if (t > 0.9) {
        alpha = opacity * ((1.0 - t) / 0.1);
      }

      // 计算位置
      final perpOffset = (drop.x - 0.5) * diag;
      final centerX = size.width / 2 + perpX * perpOffset + dx * (t - 0.5) * diag * 1.5;
      final centerY = size.height / 2 + perpY * perpOffset + dy * (t - 0.5) * diag * 1.5;

      // 绘制雨滴
      _drawRainDropWithTail(
        canvas,
        Offset(centerX, centerY),
        drop.size,
        drop.tailLength,
        color.withValues(alpha: alpha.clamp(0.0, 1.0)),
        radians,
      );
    }
  }

  void _drawRainDropWithTail(
    Canvas canvas,
    Offset position,
    double headSize,
    double tailLength,
    Color color,
    double angle,
  ) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle - pi / 2);

    // 绘制尾部（8段渐变）
    final tailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = headSize * 0.8;

    const tailSegments = 8;
    for (int i = 0; i < tailSegments; i++) {
      final segmentAlpha = color.a * (1 - i / tailSegments);
      tailPaint.color = color.withValues(alpha: segmentAlpha.clamp(0.0, 1.0));

      final startY = -headSize * 0.5 - (tailLength * headSize) * (i / tailSegments);
      final endY = -headSize * 0.5 - (tailLength * headSize) * ((i + 1) / tailSegments);
      canvas.drawLine(Offset(0, startY), Offset(0, endY), tailPaint);
    }

    // 绘制头部（水滴形状）
    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final halfWidth = headSize;
    final height = headSize * 1.8;

    path.moveTo(0, height * 0.5);
    path.quadraticBezierTo(
      halfWidth * 0.7,
      height * 0.1,
      halfWidth,
      -height * 0.1,
    );
    path.quadraticBezierTo(
      halfWidth * 0.4,
      -height * 0.5,
      0,
      -height * 0.5,
    );
    path.quadraticBezierTo(
      -halfWidth * 0.4,
      -height * 0.5,
      -halfWidth,
      -height * 0.1,
    );
    path.quadraticBezierTo(
      -halfWidth * 0.7,
      height * 0.1,
      0,
      height * 0.5,
    );
    path.close();

    canvas.drawPath(path, headPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RainPainter oldDelegate) {
    return oldDelegate.elapsedSeconds != elapsedSeconds ||
        oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.angle != angle;
  }
}

/// 雨幕渐变背景（静态）
class RainGradientBackground extends StatelessWidget {
  final Widget child;

  const RainGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  colorScheme.surfaceContainerLowest,
                  colorScheme.surface,
                  colorScheme.surface,
                ]
              : [
                  colorScheme.surfaceContainerLowest,
                  colorScheme.surfaceContainerLowest,
                  colorScheme.surface,
                ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: child,
    );
  }
}
