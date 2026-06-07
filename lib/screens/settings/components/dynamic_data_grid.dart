import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../plugin_data_controller.dart';
import '../../../utils/responsive_helper.dart';

class DynamicDataGrid extends StatelessWidget {
  const DynamicDataGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PluginDataController>();
    final tableName = controller.selectedTable;
    
    if (tableName == null) {
      return const Center(child: Text('请选择要查看的数据表'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. 顶部搜索过滤栏
        _buildFilterToolbar(context, controller, tableName),
        
        const Divider(height: 1),

        // B. 网格主体
        Expanded(
          child: controller.isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : controller.dataLoadError != null
                  ? _buildErrorWidget(context, controller)
                  : controller.pageData.isEmpty
                      ? _buildEmptyGridState(context, controller)
                      : _buildExcelGrid(context, controller, tableName),
        ),

        const Divider(height: 1),

        // C. 底部翻页控制器
        _buildPaginationFooter(context, controller),
      ],
    );
  }

  // 错误展示组件
  Widget _buildErrorWidget(BuildContext context, PluginDataController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text('读取数据表出错', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              controller.dataLoadError ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 表格空数据状态展示
  Widget _buildEmptyGridState(BuildContext context, PluginDataController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.border_all, size: 48, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            controller.activeWhereClause != null ? '没有符合筛选条件的数据' : '数据表中无数据',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (controller.activeWhereClause != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: controller.clearFilter,
              child: const Text('重置筛选'),
            ),
          ],
        ],
      ),
    );
  }

  // 顶部检索过滤栏 UI
  Widget _buildFilterToolbar(BuildContext context, PluginDataController controller, String tableName) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ResponsiveHelper.isMediumOrLarger(context);

    final filterOptions = controller.columns;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          // 移动端返回列表按钮 (仅限窄屏)
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, size: 18),
              onPressed: () {
                controller.setMobileSelectedTableNull();
              },
              tooltip: '返回表列表',
            ),

          // 表名标志
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tableName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),

          // 检索下拉
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: controller.filterColumn,
                hint: const Text('选择列进行筛选', style: TextStyle(fontSize: 13)),
                items: filterOptions.map((col) {
                  return DropdownMenuItem<String>(
                    value: col,
                    child: Text(col, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  controller.setFilterColumn(val);
                },
              ),
            ),
          ),

          // 输入匹配内容框
          SizedBox(
            width: 160,
            height: 36,
            child: TextField(
              controller: controller.filterValController,
              decoration: InputDecoration(
                hintText: '精准筛选内容...',
                hintStyle: const TextStyle(fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => controller.applyFilter(),
            ),
          ),

          // 筛选与清除按钮组
          IconButton.filledTonal(
            onPressed: controller.applyFilter,
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            tooltip: '筛选',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          
          if (controller.activeWhereClause != null)
            IconButton.outlined(
              onPressed: controller.clearFilter,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              color: colorScheme.error,
              tooltip: '清除筛选',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),

          const SizedBox(width: 8),

          // 操作按钮组
          FilledButton.tonalIcon(
            onPressed: controller.loadPageData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
          ),

          FilledButton.tonalIcon(
            onPressed: () => _exportToCsv(context, controller, tableName),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('导出 CSV', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
          ),

          OutlinedButton.icon(
            onPressed: () => _clearTable(context, controller, tableName),
            icon: Icon(Icons.delete_sweep, size: 16, color: colorScheme.error),
            label: Text('清空表', style: TextStyle(fontSize: 13, color: colorScheme.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Excel 表格 UI
  Widget _buildExcelGrid(BuildContext context, PluginDataController controller, String tableName) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    double rowNumberWidth = 50.0;
    double actionColumnWidth = 60.0;
    double totalGridWidth = rowNumberWidth + actionColumnWidth;
    for (final col in controller.columns) {
      totalGridWidth += controller.columnWidths[col] ?? 120.0;
    }

    return Scrollbar(
      controller: controller.horizontalScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: controller.horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalGridWidth,
          child: Column(
            children: [
              // Excel 表头
              _buildExcelHeader(context, controller, rowNumberWidth, actionColumnWidth),
              
              // 分割线
              Container(
                height: 1,
                color: colorScheme.outlineVariant,
              ),

              // Excel 表体
              Expanded(
                child: Scrollbar(
                  controller: controller.verticalScrollController,
                  child: ListView.builder(
                    controller: controller.verticalScrollController,
                    itemCount: controller.pageData.length,
                    itemBuilder: (context, index) {
                      return _buildExcelRow(
                        context,
                        controller,
                        index,
                        controller.pageData[index],
                        rowNumberWidth,
                        actionColumnWidth,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 表格头部行
  Widget _buildExcelHeader(
      BuildContext context, PluginDataController controller, double rowNumWidth, double actionWidth) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 38,
      color: colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          // 1. 行号头
          Container(
            width: rowNumWidth,
            height: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Text(
              '#',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          
          // 2. 数据列头
          ...controller.columns.map((col) {
            final colWidth = controller.columnWidths[col] ?? 120.0;
            return Container(
              width: colWidth,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Text(
                col,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),

          // 3. 操作列头
          Container(
            width: actionWidth,
            height: double.infinity,
            alignment: Alignment.center,
            child: Text(
              '操作',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 表格行
  Widget _buildExcelRow(
    BuildContext context,
    PluginDataController controller,
    int index,
    Map<String, dynamic> row,
    double rowNumWidth,
    double actionWidth,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool isEven = index % 2 == 0;
    final rowBgColor = isEven 
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerLowest;

    final absoluteIndex = (controller.currentPage - 1) * controller.pageSize + index + 1;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: rowBgColor,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 1. 行号
          Container(
            width: rowNumWidth,
            height: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
            ),
            child: Text(
              '$absoluteIndex',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontFamily: 'monospace',
              ),
            ),
          ),

          // 2. 字段数据格
          ...controller.columns.map((col) {
            final colWidth = controller.columnWidths[col] ?? 120.0;
            final cellValue = row[col];
            final cellStr = controller.formatCellValue(cellValue);

            return GestureDetector(
              onDoubleTap: () => _showCellDetail(context, controller, col, cellValue),
              child: Container(
                width: colWidth,
                height: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Tooltip(
                  message: '双击查看详情并复制\n内容: $cellStr',
                  waitDuration: const Duration(milliseconds: 800),
                  child: Text(
                    cellStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: (col == '_id' || cellStr.length > 20) ? 'monospace' : null,
                      color: cellValue == null ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            );
          }),

          // 3. 操作格 (删除)
          Container(
            width: actionWidth,
            height: double.infinity,
            alignment: Alignment.center,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: colorScheme.error,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _deleteRow(context, controller, row),
              tooltip: '删除此行',
            ),
          ),
        ],
      ),
    );
  }

  // 5. 底部翻页控制器 UI
  Widget _buildPaginationFooter(BuildContext context, PluginDataController controller) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalPages = max(1, (controller.totalRows / controller.pageSize).ceil());
    final isFirstPage = controller.currentPage == 1;
    final isLastPage = controller.currentPage == totalPages;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // 左侧：条数摘要
          Text(
            '共 ${controller.totalRows} 行  显示第 ${min((controller.currentPage - 1) * controller.pageSize + 1, controller.totalRows)} - ${min(controller.currentPage * controller.pageSize, controller.totalRows)} 行',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          
          const Spacer(),

          // 中间：翻页控制
          IconButton(
            icon: const Icon(Icons.first_page, size: 18),
            onPressed: isFirstPage
                ? null
                : () {
                    controller.setCurrentPage(1);
                  },
            tooltip: '首页',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: isFirstPage
                ? null
                : () {
                    controller.setCurrentPage(controller.currentPage - 1);
                  },
            tooltip: '上一页',
          ),
          
          // 页码显示及跳转
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  '第 ',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                SizedBox(
                  width: 44,
                  height: 28,
                  child: TextField(
                    controller: controller.pageJumpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    onSubmitted: (val) {
                      final targetPage = int.tryParse(val);
                      if (targetPage != null && targetPage >= 1 && targetPage <= totalPages) {
                        controller.setCurrentPage(targetPage);
                      } else {
                        controller.pageJumpController.text = controller.currentPage.toString();
                      }
                    },
                  ),
                ),
                Text(
                  ' / $totalPages 页',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: isLastPage
                ? null
                : () {
                    controller.setCurrentPage(controller.currentPage + 1);
                  },
            tooltip: '下一页',
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 18),
            onPressed: isLastPage
                ? null
                : () {
                    controller.setCurrentPage(totalPages);
                  },
            tooltip: '末页',
          ),

          const SizedBox(width: 16),

          // 右侧：每页大小选择
          Text(
            '每页 ',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: controller.pageSize,
                items: [50, 100, 200, 500, 1000].map((size) {
                  return DropdownMenuItem<int>(
                    value: size,
                    child: Text('$size 行', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    controller.setPageSize(val);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 格式化弹出层中的文本（如果是 JSON 会格式化排版）
  String _formatDetailValue(dynamic val) {
    if (val == null) return 'null';
    if (val is Map || val is List) {
      try {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(val);
      } catch (_) {
        return val.toString();
      }
    }
    if (val is String) {
      final trimmed = val.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          final decoded = jsonDecode(trimmed);
          const encoder = JsonEncoder.withIndent('  ');
          return encoder.convert(decoded);
        } catch (_) {}
      }
    }
    return val.toString();
  }

  // 双击单元格打开详情对话框
  void _showCellDetail(BuildContext context, PluginDataController controller, String columnName, dynamic rawValue) {
    final formattedValue = _formatDetailValue(rawValue);
    final isJson = formattedValue.trim().startsWith('{') || formattedValue.trim().startsWith('[');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.data_object, size: 20),
            const SizedBox(width: 8),
            Text('列: $columnName 单元格详情'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isJson ? 'JSON 结构化展示' : '文本内容',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerLowest,
                    border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      formattedValue,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制内容'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawValue?.toString() ?? ''));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已成功复制单元格数据'), duration: Duration(seconds: 1)),
              );
            },
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 删除单行
  Future<void> _deleteRow(BuildContext context, PluginDataController controller, Map<String, dynamic> row) async {
    final rowId = row['_id'];
    if (rowId == null) return;

    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 36),
        title: const Text('删除数据行'),
        content: Text('确定要删除 ID 为 #$rowId 的这行数据吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await controller.deleteRow(row);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  // 清空整张表
  Future<void> _clearTable(BuildContext context, PluginDataController controller, String tableName) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever, color: colorScheme.error, size: 36),
        title: Text('清空表: $tableName'),
        content: Text('确定要清空数据表 "$tableName" 中的所有数据吗？这会抹除全部行且不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await controller.clearTable();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清空表 "$tableName"')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('清空失败: $e')),
          );
        }
      }
    }
  }

  // 导出为 CSV 文件
  Future<void> _exportToCsv(BuildContext context, PluginDataController controller, String tableName) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在读取全量数据，请稍候...'),
            ],
          ),
        ),
      );

      final csvContent = await controller.generateCsvString();
      if (context.mounted) {
        Navigator.pop(context); // 关闭加载弹窗
      }

      if (csvContent == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前表内无可用数据导出')),
          );
        }
        return;
      }

      // 调起文件保存弹窗
      final result = await FilePicker.saveFile(
        dialogTitle: '导出 CSV 数据表',
        fileName: '${controller.pluginName}_${tableName}_data.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(utf8.encode(csvContent));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出成功：${file.path}')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}
