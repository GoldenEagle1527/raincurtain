import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../plugin_data_controller.dart';

class TablesSidebar extends StatelessWidget {
  const TablesSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PluginDataController>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 过滤表名
    final filteredTables = controller.tableNames
        .where((t) => t.toLowerCase().contains(controller.tableSearchQuery.toLowerCase()))
        .toList();

    return Column(
      children: [
        // 搜索框
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索数据表...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) {
              controller.setTableSearchQuery(val);
            },
          ),
        ),
        const Divider(height: 1),
        // 列表
        Expanded(
          child: filteredTables.isEmpty
              ? Center(
                  child: Text(
                    '无匹配的表',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filteredTables.length,
                  itemBuilder: (context, index) {
                    final tableName = filteredTables[index];
                    final isSelected = controller.selectedTable == tableName;
                    final rowCount = controller.tableRowCounts[tableName] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
                        leading: Icon(
                          Icons.table_chart_outlined,
                          size: 20,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          tableName,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '$rowCount 行',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onTap: () => controller.selectTable(tableName),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
