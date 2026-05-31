import 'package:flutter/foundation.dart';

/// 控制台日志级别
enum ConsoleLevel {
  log,
  info,
  warn,
  error,
  debug,
}

/// 单条控制台消息
class ConsoleMessage {
  final ConsoleLevel level;
  final String message;
  final DateTime timestamp;

  const ConsoleMessage({
    required this.level,
    required this.message,
    required this.timestamp,
  });
}

/// 控制台状态管理器
///
/// 管理 WebView 中 console.* 输出的日志列表，
/// 支持按级别过滤、清除、面板显隐切换。
class ConsoleManager extends ChangeNotifier {
  /// 最大日志条数，超出后自动淘汰最早的
  static const int maxMessages = 1000;

  final List<ConsoleMessage> _messages = [];
  Set<ConsoleLevel> _activeFilters = ConsoleLevel.values.toSet();
  bool _isVisible = false;

  /// 各级别的增量计数器，O(1) 查询
  final Map<ConsoleLevel, int> _levelCounts = {
    for (final level in ConsoleLevel.values) level: 0,
  };

  /// 所有原始日志
  List<ConsoleMessage> get messages => List.unmodifiable(_messages);

  /// 按当前过滤条件筛选后的日志
  List<ConsoleMessage> get filteredMessages {
    if (_activeFilters.length == ConsoleLevel.values.length) {
      // 全部级别都激活时，直接返回不筛选
      return List.unmodifiable(_messages);
    }
    return _messages
        .where((m) => _activeFilters.contains(m.level))
        .toList();
  }

  /// 面板是否可见
  bool get isVisible => _isVisible;

  /// 当前激活的过滤级别
  Set<ConsoleLevel> get activeFilters => Set.unmodifiable(_activeFilters);

  /// 各级别的未过滤消息数量（O(1)，用于 badge 显示）
  int countByLevel(ConsoleLevel level) => _levelCounts[level] ?? 0;

  /// 添加一条日志
  void addMessage(ConsoleLevel level, String message) {
    _messages.add(ConsoleMessage(
      level: level,
      message: message,
      timestamp: DateTime.now(),
    ));
    _levelCounts[level] = (_levelCounts[level] ?? 0) + 1;

    // 超出上限时移除最早的消息
    if (_messages.length > maxMessages) {
      final removed = _messages.removeAt(0);
      _levelCounts[removed.level] = (_levelCounts[removed.level] ?? 1) - 1;
    }
    notifyListeners();
  }

  /// 清除所有日志
  void clear() {
    _messages.clear();
    for (final level in ConsoleLevel.values) {
      _levelCounts[level] = 0;
    }
    notifyListeners();
  }

  /// 切换面板显隐
  void toggleVisibility() {
    _isVisible = !_isVisible;
    notifyListeners();
  }

  /// 隐藏面板
  void hide() {
    if (_isVisible) {
      _isVisible = false;
      notifyListeners();
    }
  }

  /// 切换某个级别的过滤状态
  void toggleFilter(ConsoleLevel level) {
    if (_activeFilters.contains(level)) {
      _activeFilters.remove(level);
    } else {
      _activeFilters.add(level);
    }
    notifyListeners();
  }
}
