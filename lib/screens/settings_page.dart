import 'dart:io';
import 'package:flutter/material.dart';
import 'settings/theme_settings_tab.dart';
import 'settings/data_management_tab.dart';
import 'settings/rain_settings_tab.dart';
import 'settings/hotkey_settings_tab.dart';

/// 设置页面
/// 包含主题设置、雨幕效果和数据管理三个标签页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Windows平台有4个标签页,其他平台3个
    _tabController = TabController(
      length: Platform.isWindows ? 4 : 3,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const Tab(icon: Icon(Icons.palette), text: '主题'),
      const Tab(icon: Icon(Icons.water_drop), text: '雨幕'),
      const Tab(icon: Icon(Icons.storage), text: '数据管理'),
      if (Platform.isWindows)
        const Tab(icon: Icon(Icons.keyboard), text: '快捷键'),
    ];

    final tabViews = [
      const ThemeSettingsTab(),
      const RainSettingsTab(),
      const DataManagementTab(),
      if (Platform.isWindows) const HotkeySettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: tabViews,
      ),
    );
  }
}
