import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tab_manager.dart';
import '../../widgets/theme_toggle_button.dart';

class HomeDrawer extends StatelessWidget {
  final VoidCallback? onConsoleTap;

  const HomeDrawer({
    super.key,
    this.onConsoleTap,
  });

  @override
  Widget build(BuildContext context) {
    final tabManager = context.watch<TabManager>();

    return Drawer(
      child: Column(
        children: [
          // 顶部安全区域间距
          SizedBox(height: MediaQuery.of(context).padding.top + 8),
          // 标签列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: tabManager.tabs.length,
              itemBuilder: (context, index) {
                final tab = tabManager.tabs[index];
                final isSelected = tabManager.currentIndex == index;

                return ListTile(
                  selected: isSelected,
                  leading: Icon(
                    tab.plugin == null ? Icons.store : Icons.extension,
                  ),
                  title: Text(tab.title),
                  subtitle: tab.plugin == null
                      ? const Text('插件市场')
                      : Text(
                          '${tab.plugin!.author} · v${tab.plugin!.version}\n${tab.plugin!.description}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  isThreeLine: tab.plugin != null,
                  trailing: tab.plugin != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          iconSize: 20,
                          onPressed: () {
                            tabManager.closeTab(index);
                            Navigator.pop(context);
                          },
                          tooltip: '关闭',
                        )
                      : null,
                  onTap: () {
                    tabManager.switchToTab(index);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          // 分割线
          const Divider(),
          // 打开控制台（仅当前 tab 是插件时显示）
          if (tabManager.currentTab.plugin != null)
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('控制台'),
              onTap: () {
                Navigator.pop(context);
                onConsoleTap?.call();
              },
            ),
          // 主题切换分段按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: ThemeToggleSegmentedButton(),
          ),
        ],
      ),
    );
  }
}
