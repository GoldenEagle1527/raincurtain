import 'package:flutter/material.dart';

class SplitPane extends StatefulWidget {
  final Widget mainContent;
  final Widget secondaryContent;
  final bool isVertical; // true: 垂直排列(上下); false: 水平排列(左右)
  final double initialFraction;
  final double minFraction;
  final double maxFraction;
  final double dividerThickness;

  const SplitPane({
    super.key,
    required this.mainContent,
    required this.secondaryContent,
    this.isVertical = true,
    this.initialFraction = 0.35,
    this.minFraction = 0.15,
    this.maxFraction = 0.85,
    this.dividerThickness = 8.0,
  });

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  late double _fraction;

  @override
  void initState() {
    super.initState();
    _fraction = widget.initialFraction;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.isVertical) {
          final totalHeight = constraints.maxHeight;
          final secondaryHeight = (totalHeight * _fraction)
              .clamp(widget.dividerThickness + 80, totalHeight - 80);
          final mainHeight = totalHeight - secondaryHeight - widget.dividerThickness;

          return Column(
            children: [
              SizedBox(height: mainHeight, child: widget.mainContent),
              _buildHorizontalDragHandle(colorScheme, totalHeight),
              SizedBox(height: secondaryHeight, child: widget.secondaryContent),
            ],
          );
        } else {
          final totalWidth = constraints.maxWidth;
          final secondaryWidth = (totalWidth * _fraction)
              .clamp(widget.dividerThickness + 200, totalWidth - 200);
          final mainWidth = totalWidth - secondaryWidth - widget.dividerThickness;

          return Row(
            children: [
              SizedBox(width: mainWidth, child: widget.mainContent),
              _buildVerticalDragHandle(colorScheme, totalWidth),
              SizedBox(width: secondaryWidth, child: widget.secondaryContent),
            ],
          );
        }
      },
    );
  }

  Widget _buildHorizontalDragHandle(ColorScheme colorScheme, double totalSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        setState(() {
          _fraction -= details.primaryDelta! / totalSize;
          _fraction = _fraction.clamp(widget.minFraction, widget.maxFraction);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: Container(
          height: widget.dividerThickness,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          child: Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalDragHandle(ColorScheme colorScheme, double totalSize) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _fraction -= details.primaryDelta! / totalSize;
          _fraction = _fraction.clamp(widget.minFraction, widget.maxFraction);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: widget.dividerThickness,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          child: Center(
            child: Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
