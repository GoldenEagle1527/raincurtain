import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plugin_data_manager.dart';
import '../../utils/responsive_helper.dart';
import 'plugin_data_controller.dart';
import 'components/tables_sidebar.dart';
import 'components/dynamic_data_grid.dart';

/// 插件数据详情页面
/// 显示单个插件的存储表及其类似于 Excel 的数据网格，支持大数据展示性能优化
class PluginDataDetailsPage extends StatelessWidget {
  final String pluginId;
  final String pluginName;

  const PluginDataDetailsPage({
    super.key,
    required this.pluginId,
    required this.pluginName,
  });

  @override
  Widget build(BuildContext context) {
    final dataManager = context.read<PluginDataManager>();

    return ChangeNotifierProvider<PluginDataController>(
      create: (_) => PluginDataController(
        pluginId: pluginId,
        pluginName: pluginName,
        storageManager: dataManager.pluginStorageManager,
      ),
      child: Consumer<PluginDataController>(
        builder: (context, controller, child) {
          final isDesktop = ResponsiveHelper.isMediumOrLarger(context);

          return Scaffold(
            appBar: AppBar(
              title: Text('$pluginName - 数据详情'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // 如果在移动端视图处于数据网格，点击返回时回到表列表
                  if (!isDesktop && controller.selectedTableForMobile != null) {
                    controller.setMobileSelectedTableNull();
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            body: controller.isLoadingTables
                ? const Center(child: CircularProgressIndicator())
                : controller.tableNames.isEmpty
                    ? _buildEmptyState(context)
                    : isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 左侧表名列表 (280dp)
                              Container(
                                width: 280,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                                child: const TablesSidebar(),
                              ),
                              // 右侧数据网格
                              const Expanded(
                                child: DynamicDataGrid(),
                              ),
                            ],
                          )
                        : controller.selectedTableForMobile == null
                            ? const TablesSidebar() // 移动端展示表列表
                            : const DynamicDataGrid(), // 移动端展示网格
          );
        },
      ),
    );
  }

  // 1. 无数据表空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '该插件暂无任何存储数据',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
