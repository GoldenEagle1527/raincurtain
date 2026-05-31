import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/console_manager.dart' as console_model;

/// 悬浮控制台面板
///
/// 模拟浏览器 DevTools Console 面板，显示 WebView 的 console 输出，
/// 支持按级别过滤、清除日志、输入 JS 表达式执行。
class ConsolePanel extends StatefulWidget {
  final console_model.ConsoleManager consoleManager;

  /// WebView 控制器，用于执行 JS 表达式
  final InAppWebViewController? webViewController;

  /// 关闭面板回调
  final VoidCallback onClose;

  const ConsolePanel({
    super.key,
    required this.consoleManager,
    required this.webViewController,
    required this.onClose,
  });

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  /// 是否自动滚动到底部
  bool _autoScroll = true;

  /// 防止同一帧内多次注册 addPostFrameCallback
  bool _scrollPending = false;

  @override
  void initState() {
    super.initState();
    widget.consoleManager.addListener(_onConsoleChanged);
  }

  @override
  void didUpdateWidget(covariant ConsolePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.consoleManager != widget.consoleManager) {
      oldWidget.consoleManager.removeListener(_onConsoleChanged);
      widget.consoleManager.addListener(_onConsoleChanged);
    }
  }

  @override
  void dispose() {
    widget.consoleManager.removeListener(_onConsoleChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onConsoleChanged() {
    setState(() {});
    if (_autoScroll && !_scrollPending) {
      _scrollPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPending = false;
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent,
      );
    }
  }

  /// 执行 JS 表达式
  Future<void> _executeJS() async {
    final code = _inputController.text.trim();
    if (code.isEmpty) return;

    // 将输入记录为一条 log 消息（带 > 前缀标识输入）
    widget.consoleManager.addMessage(console_model.ConsoleLevel.info, '> $code');
    _inputController.clear();

    if (widget.webViewController == null) {
      widget.consoleManager.addMessage(
        console_model.ConsoleLevel.error,
        'WebView 未就绪，无法执行',
      );
      return;
    }

    try {
      final result = await widget.webViewController!.evaluateJavascript(
        source: '''
(function() {
  try {
    var __result = eval(${_escapeJSString(code)});
    if (__result === undefined) return 'undefined';
    if (__result === null) return 'null';
    if (typeof __result === 'object') {
      try { return JSON.stringify(__result, null, 2); }
      catch(e) { return String(__result); }
    }
    return String(__result);
  } catch(e) {
    return '❌ ' + e.toString();
  }
})()
''',
      );

      if (result != null) {
        final resultStr = result.toString();
        // 判断是否是错误结果
        if (resultStr.startsWith('❌ ')) {
          widget.consoleManager.addMessage(
            console_model.ConsoleLevel.error,
            resultStr.substring(2),
          );
        } else {
          widget.consoleManager.addMessage(console_model.ConsoleLevel.log, '← $resultStr');
        }
      }
    } catch (e) {
      widget.consoleManager.addMessage(console_model.ConsoleLevel.error, e.toString());
    }
  }

  /// 将 Dart 字符串转义为 JS 字符串字面量
  String _escapeJSString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return "'$escaped'";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final messages = widget.consoleManager.filteredMessages;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      surfaceTintColor: colorScheme.primary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽手柄 + 标题栏
          _buildHeader(colorScheme, messages.length),
          // 过滤器工具栏
          _buildFilterBar(colorScheme),
          const Divider(height: 1),
          // 日志列表
          Expanded(
            child: _buildMessageList(colorScheme, messages),
          ),
          const Divider(height: 1),
          // JS 输入框
          _buildInputBar(colorScheme),
        ],
      ),
    );
  }

  /// 标题栏：拖拽手柄 + 标题 + 关闭按钮
  Widget _buildHeader(ColorScheme colorScheme, int messageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // 拖拽手柄指示器
          Expanded(
            child: Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.terminal,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '控制台',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // 消息计数
          Text(
            '$messageCount 条',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 4),
          // 清除按钮
          _buildHeaderAction(
            icon: Icons.delete_outline,
            tooltip: '清除日志',
            onPressed: widget.consoleManager.clear,
            colorScheme: colorScheme,
          ),
          // 自动滚动切换
          _buildHeaderAction(
            icon: _autoScroll
                ? Icons.vertical_align_bottom
                : Icons.vertical_align_bottom_outlined,
            tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            colorScheme: colorScheme,
            isActive: _autoScroll,
          ),
          // 关闭按钮
          _buildHeaderAction(
            icon: Icons.close,
            tooltip: '关闭控制台',
            onPressed: widget.onClose,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
    bool isActive = false,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// 过滤器工具栏
  Widget _buildFilterBar(ColorScheme colorScheme) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _buildFilterChip(console_model.ConsoleLevel.log, 'Log', colorScheme),
          const SizedBox(width: 4),
          _buildFilterChip(console_model.ConsoleLevel.info, 'Info', colorScheme),
          const SizedBox(width: 4),
          _buildFilterChip(console_model.ConsoleLevel.warn, 'Warn', colorScheme),
          const SizedBox(width: 4),
          _buildFilterChip(console_model.ConsoleLevel.error, 'Error', colorScheme),
          const SizedBox(width: 4),
          _buildFilterChip(console_model.ConsoleLevel.debug, 'Debug', colorScheme),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    console_model.ConsoleLevel level,
    String label,
    ColorScheme colorScheme,
  ) {
    final isActive = widget.consoleManager.activeFilters.contains(level);
    final count = widget.consoleManager.countByLevel(level);
    final chipColor = _getLevelColor(level, colorScheme);

    return GestureDetector(
      onTap: () => widget.consoleManager.toggleFilter(level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? chipColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? chipColor.withValues(alpha: 0.4)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? chipColor : colorScheme.onSurfaceVariant,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: chipColor,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 日志列表
  Widget _buildMessageList(
    ColorScheme colorScheme,
    List<console_model.ConsoleMessage> messages,
  ) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 32,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              '暂无日志输出',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        return _buildMessageItem(messages[index], colorScheme, index);
      },
    );
  }

  /// 单条日志
  Widget _buildMessageItem(
    console_model.ConsoleMessage msg,
    ColorScheme colorScheme,
    int index,
  ) {
    final levelColor = _getLevelColor(msg.level, colorScheme);
    final bgColor = _getLevelBgColor(msg.level, colorScheme, index);
    final time =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
        '${msg.timestamp.minute.toString().padLeft(2, '0')}:'
        '${msg.timestamp.second.toString().padLeft(2, '0')}.'
        '${msg.timestamp.millisecond.toString().padLeft(3, '0')}';

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间戳
          Text(
            time,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          // 级别标签
          Container(
            width: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _getLevelLabel(msg.level),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: levelColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 消息内容
          Expanded(
            child: SelectableText(
              msg.message,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: _getMessageTextColor(msg.level, colorScheme),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// JS 输入框
  Widget _buildInputBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Text(
            '>',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocusNode,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: '输入 JavaScript 表达式...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              onSubmitted: (_) => _executeJS(),
              textInputAction: TextInputAction.send,
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              icon: Icon(
                Icons.play_arrow,
                size: 18,
                color: colorScheme.primary,
              ),
              tooltip: '执行',
              onPressed: _executeJS,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 颜色/标签映射 ───

  Color _getLevelColor(console_model.ConsoleLevel level, ColorScheme colorScheme) {
    switch (level) {
      case console_model.ConsoleLevel.log:
        return colorScheme.onSurface;
      case console_model.ConsoleLevel.info:
        return colorScheme.primary;
      case console_model.ConsoleLevel.warn:
        return Colors.orange;
      case console_model.ConsoleLevel.error:
        return colorScheme.error;
      case console_model.ConsoleLevel.debug:
        return colorScheme.onSurfaceVariant;
    }
  }

  Color _getLevelBgColor(
    console_model.ConsoleLevel level,
    ColorScheme colorScheme,
    int index,
  ) {
    switch (level) {
      case console_model.ConsoleLevel.warn:
        return Colors.orange.withValues(alpha: 0.06);
      case console_model.ConsoleLevel.error:
        return colorScheme.error.withValues(alpha: 0.06);
      default:
        // 奇偶行交替底色
        return index.isEven
            ? Colors.transparent
            : colorScheme.onSurface.withValues(alpha: 0.02);
    }
  }

  Color _getMessageTextColor(console_model.ConsoleLevel level, ColorScheme colorScheme) {
    switch (level) {
      case console_model.ConsoleLevel.error:
        return colorScheme.error;
      case console_model.ConsoleLevel.warn:
        return Colors.orange.shade800;
      case console_model.ConsoleLevel.debug:
        return colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
      default:
        return colorScheme.onSurface;
    }
  }

  String _getLevelLabel(console_model.ConsoleLevel level) {
    switch (level) {
      case console_model.ConsoleLevel.log:
        return 'LOG';
      case console_model.ConsoleLevel.info:
        return 'INFO';
      case console_model.ConsoleLevel.warn:
        return 'WARN';
      case console_model.ConsoleLevel.error:
        return 'ERR';
      case console_model.ConsoleLevel.debug:
        return 'DBG';
    }
  }
}
