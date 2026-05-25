import 'package:flutter/foundation.dart';
import 'plugin_manager.dart';

class TabItem {
  final String id;
  final LocalPlugin? plugin; // if null, it's the home/market page
  final String title;

  TabItem({required this.id, this.plugin, required this.title});
}

class TabManager extends ChangeNotifier {
  final List<TabItem> _tabs = [
    TabItem(id: 'home', title: '应用市场'),
  ];
  
  int _currentIndex = 0;

  List<TabItem> get tabs => _tabs;
  int get currentIndex => _currentIndex;
  TabItem get currentTab => _tabs[_currentIndex];

  void openOrSwitchTab(LocalPlugin plugin) {
    // Check if plugin is already open
    final existingIndex = _tabs.indexWhere((t) => t.plugin?.id == plugin.id);
    if (existingIndex != -1) {
      _currentIndex = existingIndex;
    } else {
      _tabs.add(TabItem(
        id: 'tab_${plugin.id}',
        plugin: plugin,
        title: plugin.name,
      ));
      _currentIndex = _tabs.length - 1;
    }
    notifyListeners();
  }

  void switchToTab(int index) {
    if (index >= 0 && index < _tabs.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  void closeTab(int index) {
    if (index == 0) return; // Cannot close home tab
    _tabs.removeAt(index);
    if (_currentIndex >= index) {
      _currentIndex--;
    }
    notifyListeners();
  }

  /// 关闭除指定 index 之外的所有可关闭标签页 (保留 home tab)
  void closeOtherTabs(int keepIndex) {
    if (keepIndex < 0 || keepIndex >= _tabs.length) return;
    final keepTab = _tabs[keepIndex];
    _tabs.removeWhere((t) => t.id != 'home' && t.id != keepTab.id);
    _currentIndex = _tabs.indexOf(keepTab);
    if (_currentIndex < 0) _currentIndex = 0;
    notifyListeners();
  }

  /// 关闭指定 index 右侧的所有标签页
  void closeTabsToRight(int index) {
    if (index < 0 || index >= _tabs.length - 1) return;
    _tabs.removeRange(index + 1, _tabs.length);
    if (_currentIndex > index) {
      _currentIndex = index;
    }
    notifyListeners();
  }
}
