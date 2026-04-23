import 'package:flutter/material.dart';

/// MD3 风格的可关闭标签组件
/// 用于 TabBar 中显示带图标、文字和可选关闭按钮的标签
class CloseableTab extends StatelessWidget {
  /// 标签图标
  final IconData icon;
  
  /// 标签文字
  final String text;
  
  /// 是否显示关闭按钮
  final bool showCloseButton;
  
  /// 关闭按钮点击回调
  final VoidCallback? onClose;
  
  /// 文字最大长度（超出会截断）
  final int maxTextLength;

  const CloseableTab({
    super.key,
    required this.icon,
    required this.text,
    this.showCloseButton = false,
    this.onClose,
    this.maxTextLength = 15,
  });

  /// 截断文字
  String _truncateText(String text) {
    if (text.length <= maxTextLength) return text;
    return '${text.substring(0, maxTextLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 图标
        Icon(
          icon,
          size: 18,
        ),
        const SizedBox(width: 8),
        // 文字
        Flexible(
          child: Text(
            _truncateText(text),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        // 关闭按钮（如果需要）
        if (showCloseButton) ...[
          const SizedBox(width: 8),
          // 使用 GestureDetector 包装，阻止事件冒泡到 TabBar
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// MD3 风格的标签数据
/// 包含标签的元数据信息
class MD3TabData {
  /// 标签图标
  final IconData icon;
  
  /// 标签标题
  final String title;
  
  /// 是否可关闭
  final bool closable;
  
  /// 关闭回调
  final VoidCallback? onClose;

  const MD3TabData({
    required this.icon,
    required this.title,
    this.closable = false,
    this.onClose,
  });

  /// 创建 Tab widget
  Tab toTab({int maxTextLength = 15}) {
    return Tab(
      child: CloseableTab(
        icon: icon,
        text: title,
        showCloseButton: closable,
        onClose: onClose,
        maxTextLength: maxTextLength,
      ),
    );
  }
}