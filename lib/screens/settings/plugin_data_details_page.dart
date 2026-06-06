import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/plugin_data_manager.dart';
import '../../utils/responsive_helper.dart';

/// 插件数据详情页面
/// 显示单个插件的存储表及其类似于 Excel 的数据网格，支持大数据展示性能优化
class PluginDataDetailsPage extends StatefulWidget {
  final String pluginId;
  final String pluginName;

  const PluginDataDetailsPage({
    super.key,
    required this.pluginId,
    required this.pluginName,
  });

  @override
  State<PluginDataDetailsPage> createState() => _PluginDataDetailsPageState();
}

class _PluginDataDetailsPageState extends State<PluginDataDetailsPage> {
  // 表格状态
  List<String> _tableNames = [];
  String? _selectedTable;
  bool _isLoadingTables = true;
  String _tableSearchQuery = '';

  // 每个表行数的缓存，以便在左侧列表显示行数 (tableName -> rowCount)
  final Map<String, int> _tableRowCounts = {};

  // 当前选中表的数据状态
  List<Map<String, dynamic>> _pageData = [];
  List<String> _columns = [];
  Map<String, double> _columnWidths = {};
  bool _isLoadingData = false;
  String? _dataLoadError;

  // 分页状态
  int _currentPage = 1;
  int _pageSize = 100;
  int _totalRows = 0;

  // 过滤状态
  String? _filterColumn;
  final TextEditingController _filterValController = TextEditingController();
  Map<String, dynamic>? _activeWhereClause;

  // 手机端自适应导航状态（在窄屏下，控制是显示表列表还是显示当前网格）
  String? _selectedTableForMobile;

  // 页码跳转输入框
  final TextEditingController _pageJumpController = TextEditingController();

  // 滚动控制器，明确指定以防止 "Scrollbar's ScrollController has no ScrollPosition attached" 的异常
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  @override
  void dispose() {
    _filterValController.dispose();
    _pageJumpController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  // 1. 加载表列表及各表行数
  Future<void> _loadTables() async {
    setState(() {
      _isLoadingTables = true;
    });

    try {
      final dataManager = context.read<PluginDataManager>();
      final tables = await dataManager.pluginStorageManager.getShortTableNames(widget.pluginId);
      
      _tableRowCounts.clear();
      for (final table in tables) {
        final count = await dataManager.pluginStorageManager.count(widget.pluginId, table, null);
        _tableRowCounts[table] = count;
      }

      if (mounted) {
        setState(() {
          _tableNames = tables;
          _isLoadingTables = false;
          
          // 默认选中第一个表
          if (tables.isNotEmpty) {
            _selectTable(tables.first);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTables = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据表失败: $e')),
        );
      }
    }
  }

  // 切换选中表
  void _selectTable(String tableName) {
    setState(() {
      _selectedTable = tableName;
      _selectedTableForMobile = tableName;
      _currentPage = 1;
      _pageJumpController.text = '1';
      // 重置过滤
      _filterColumn = null;
      _filterValController.clear();
      _activeWhereClause = null;
    });

    // 异步重置滚动条位置，防止切换表时继承上一个表的滚动条偏移
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalScrollController.hasClients) {
        _horizontalScrollController.jumpTo(0.0);
      }
      if (_verticalScrollController.hasClients) {
        _verticalScrollController.jumpTo(0.0);
      }
    });

    _loadPageData();
  }

  // 2. 加载当前页的数据 (分页 & 过滤)
  Future<void> _loadPageData() async {
    final tableName = _selectedTable;
    if (tableName == null) return;

    setState(() {
      _isLoadingData = true;
      _dataLoadError = null;
    });

    try {
      final dataManager = context.read<PluginDataManager>();
      final storage = dataManager.pluginStorageManager;

      // 查出该过滤条件下的总行数
      final total = await storage.count(
        widget.pluginId,
        tableName,
        _activeWhereClause,
      );

      // 查询分页数据
      final offset = (_currentPage - 1) * _pageSize;
      final rows = await storage.query(
        widget.pluginId,
        tableName,
        where: _activeWhereClause,
        limit: _pageSize,
        offset: offset,
        orderBy: '_id DESC', // 默认按主键倒序，显示最新数据
      );

      // 提取列名
      final colSet = <String>{'_id'};
      for (final row in rows) {
        colSet.addAll(row.keys);
      }
      final columnsList = colSet.toList();

      // 动态计算列宽
      final widths = _calculateColumnWidths(rows, columnsList);

      if (mounted) {
        setState(() {
          _totalRows = total;
          _pageData = rows;
          _columns = columnsList;
          _columnWidths = widths;
          _isLoadingData = false;
          _pageJumpController.text = _currentPage.toString();
          
          // 更新左侧列表该表的实时总行数（无过滤时的计数）
          if (_activeWhereClause == null) {
            _tableRowCounts[tableName] = total;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageData = [];
          _columns = [];
          _columnWidths = {};
          _totalRows = 0;
          _isLoadingData = false;
          _dataLoadError = e.toString();
        });
      }
    }
  }

  // 实时自适应列宽算法
  Map<String, double> _calculateColumnWidths(
      List<Map<String, dynamic>> rows, List<String> columns) {
    final widths = <String, double>{};
    for (final col in columns) {
      if (col == '_id') {
        widths[col] = 75.0; // 主键列固定略窄
        continue;
      }
      
      // 算出该列头文字的最大长度
      double maxLen = col.length.toDouble();
      for (final row in rows) {
        final val = row[col];
        if (val != null) {
          final strVal = _formatCellValue(val);
          // 中文字符宽度一般为英文字符的 2 倍，估算字符显示宽度
          double visualLength = 0;
          for (int i = 0; i < strVal.length; i++) {
            final char = strVal.codeUnitAt(i);
            visualLength += (char > 127) ? 1.8 : 1.0;
          }
          if (visualLength > maxLen) {
            maxLen = visualLength;
          }
        }
      }
      
      // 每个单位宽度约 8dp，加上内边距和操作留白
      // 限制最小宽度为 120dp，最大宽度为 360dp，保证表格整体规整
      widths[col] = (45.0 + maxLen * 7.5).clamp(120.0, 360.0);
    }
    return widths;
  }

  // 格式化展示单元格
  String _formatCellValue(dynamic val) {
    if (val == null) return 'null';
    if (val is bool) return val ? 'true' : 'false';
    if (val is Map || val is List) {
      try {
        return jsonEncode(val);
      } catch (_) {
        return val.toString();
      }
    }
    return val.toString();
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

  // 执行过滤筛选
  void _applyFilter() {
    final col = _filterColumn;
    final val = _filterValController.text.trim();

    if (col == null || val.isEmpty) {
      setState(() {
        _activeWhereClause = null;
        _currentPage = 1;
      });
    } else {
      setState(() {
        // 根据 SQLite 字段特性建立等值查询
        // 如果是数字，尝试转为数字，否则作为 String 匹配
        dynamic queryVal = val;
        final numVal = num.tryParse(val);
        if (numVal != null) {
          queryVal = numVal;
        } else if (val.toLowerCase() == 'true') {
          queryVal = 1; // bool 在 db 里存 1/0
        } else if (val.toLowerCase() == 'false') {
          queryVal = 0;
        }
        
        _activeWhereClause = {col: queryVal};
        _currentPage = 1;
      });
    }
    _loadPageData();
  }

  // 清除过滤
  void _clearFilter() {
    setState(() {
      _filterValController.clear();
      _activeWhereClause = null;
      _currentPage = 1;
    });
    _loadPageData();
  }

  // 删除单行
  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final tableName = _selectedTable;
    if (tableName == null) return;
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

    if (confirmed == true && mounted) {
      try {
        final dataManager = context.read<PluginDataManager>();
        await dataManager.pluginStorageManager.delete(
          widget.pluginId,
          tableName,
          {'_id': rowId},
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
        
        // 重新加载数据
        await _loadTables(); // 同时刷新左侧统计
        _loadPageData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  // 清空整张表
  Future<void> _clearTable() async {
    final tableName = _selectedTable;
    if (tableName == null) return;

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

    if (confirmed == true && mounted) {
      try {
        final dataManager = context.read<PluginDataManager>();
        await dataManager.pluginStorageManager.clear(widget.pluginId, tableName);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空表 "$tableName"')),
        );
        
        // 重置状态
        setState(() {
          _currentPage = 1;
        });
        await _loadTables();
        _loadPageData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败: $e')),
        );
      }
    }
  }

  // 导出为 CSV 文件
  Future<void> _exportToCsv() async {
    final tableName = _selectedTable;
    if (tableName == null || _columns.isEmpty) return;

    try {
      final dataManager = context.read<PluginDataManager>();
      
      // 导出需要获取当前表的全量数据，而非当前页
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

      final allRows = await dataManager.pluginStorageManager.query(
        widget.pluginId,
        tableName,
        where: _activeWhereClause, // 导出过滤后的全量数据
        orderBy: '_id DESC',
      );

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载弹窗

      if (allRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前表内无可用数据导出')),
          );
        }
        return;
      }

      // 拼接 CSV 文件内容（UTF-8 BOM 头，以解决 Excel 打开中文乱码）
      final buffer = StringBuffer();
      buffer.write('\uFEFF');
      
      // 表头
      buffer.writeln(_columns.map((col) => '"${col.replaceAll('"', '""')}"').join(','));
      
      // 表行数据
      for (final row in allRows) {
        final rowCsv = _columns.map((col) {
          final val = row[col];
          if (val == null) return '';
          final strVal = _formatCellValue(val);
          return '"${strVal.replaceAll('"', '""')}"';
        }).join(',');
        buffer.writeln(rowCsv);
      }

      final csvContent = buffer.toString();
      
      // 调起文件保存弹窗
      final result = await FilePicker.saveFile(
        dialogTitle: '导出 CSV 数据表',
        fileName: '${widget.pluginName}_${tableName}_data.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(utf8.encode(csvContent));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出成功：${file.path}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  // 双击单元格打开详情对话框
  void _showCellDetail(String columnName, dynamic rawValue) {
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveHelper.isMediumOrLarger(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.pluginName} - 数据详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 如果在移动端视图处于数据网格，点击返回时回到表列表
            if (!isDesktop && _selectedTableForMobile != null) {
              setState(() {
                _selectedTableForMobile = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _isLoadingTables
          ? const Center(child: CircularProgressIndicator())
          : _tableNames.isEmpty
              ? _buildEmptyState()
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
                          child: _buildTablesSidebar(),
                        ),
                        // 右侧数据网格
                        Expanded(
                          child: _buildDataGridContent(),
                        ),
                      ],
                    )
                  : _selectedTableForMobile == null
                      ? _buildTablesSidebar() // 移动端展示表列表
                      : _buildDataGridContent(), // 移动端展示网格
    );
  }

  // 1. 无数据表空状态
  Widget _buildEmptyState() {
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

  // 2. 左侧表列表侧边栏 (带表过滤搜索)
  Widget _buildTablesSidebar() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 过滤表名
    final filteredTables = _tableNames
        .where((t) => t.toLowerCase().contains(_tableSearchQuery.toLowerCase()))
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
              setState(() {
                _tableSearchQuery = val;
              });
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
                    final isSelected = _selectedTable == tableName;
                    final rowCount = _tableRowCounts[tableName] ?? 0;

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
                        onTap: () => _selectTable(tableName),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 3. 右侧主 Excel 网格内容区
  Widget _buildDataGridContent() {
    final tableName = _selectedTable;
    if (tableName == null) {
      return const Center(child: Text('请选择要查看的数据表'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. 顶部搜索过滤栏
        _buildFilterToolbar(tableName),
        
        const Divider(height: 1),

        // B. 网格主体
        Expanded(
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : _dataLoadError != null
                  ? _buildErrorWidget()
                  : _pageData.isEmpty
                      ? _buildEmptyGridState(tableName)
                      : _buildExcelGrid(tableName),
        ),

        const Divider(height: 1),

        // C. 底部翻页控制器
        _buildPaginationFooter(),
      ],
    );
  }

  // 错误展示组件
  Widget _buildErrorWidget() {
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
              _dataLoadError ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 表格空数据状态展示
  Widget _buildEmptyGridState(String tableName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.border_all, size: 48, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            _activeWhereClause != null ? '没有符合筛选条件的数据' : '数据表中无数据',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_activeWhereClause != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _clearFilter,
              child: const Text('重置筛选'),
            ),
          ],
        ],
      ),
    );
  }

  // 顶部检索过滤栏 UI
  Widget _buildFilterToolbar(String tableName) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ResponsiveHelper.isMediumOrLarger(context);

    // 下拉列过滤选项包含 _id 和所有当前页的数据键
    final filterOptions = _columns;

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
                setState(() {
                  _selectedTableForMobile = null;
                });
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
                value: _filterColumn,
                hint: const Text('选择列进行筛选', style: TextStyle(fontSize: 13)),
                items: filterOptions.map((col) {
                  return DropdownMenuItem<String>(
                    value: col,
                    child: Text(col, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _filterColumn = val;
                  });
                },
              ),
            ),
          ),

          // 输入匹配内容框
          SizedBox(
            width: 160,
            height: 36,
            child: TextField(
              controller: _filterValController,
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
              onSubmitted: (_) => _applyFilter(),
            ),
          ),

          // 筛选与清除按钮组
          IconButton.filledTonal(
            onPressed: _applyFilter,
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            tooltip: '筛选',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          
          if (_activeWhereClause != null)
            IconButton.outlined(
              onPressed: _clearFilter,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              color: colorScheme.error,
              tooltip: '清除筛选',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),

          const SizedBox(width: 8),

          // 操作按钮组
          FilledButton.tonalIcon(
            onPressed: _loadPageData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('刷新', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
          ),

          FilledButton.tonalIcon(
            onPressed: _exportToCsv,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('导出 CSV', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 36),
            ),
          ),

          OutlinedButton.icon(
            onPressed: _clearTable,
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

  // 4. Excel 表格 UI（高性能横纵滚动同步网格）
  Widget _buildExcelGrid(String tableName) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // 计算总宽度 = 行号列宽度 (50.0) + 操作列宽度 (60.0) + 所有数据列宽度之和
    double rowNumberWidth = 50.0;
    double actionColumnWidth = 60.0;
    double totalGridWidth = rowNumberWidth + actionColumnWidth;
    for (final col in _columns) {
      totalGridWidth += _columnWidths[col] ?? 120.0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalGridWidth,
              child: Column(
                children: [
                  // Excel 表头
                  _buildExcelHeader(rowNumberWidth, actionColumnWidth),
                  
                  // 分割线
                  Container(
                    height: 1,
                    color: colorScheme.outlineVariant,
                  ),

                  // Excel 表体（虚拟滚动的列表）
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: _pageData.length,
                        itemBuilder: (context, index) {
                          return _buildExcelRow(index, _pageData[index], rowNumberWidth, actionColumnWidth);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 表格头部行
  Widget _buildExcelHeader(double rowNumWidth, double actionWidth) {
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
          ..._columns.map((col) {
            final colWidth = _columnWidths[col] ?? 120.0;
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
  Widget _buildExcelRow(int index, Map<String, dynamic> row, double rowNumWidth, double actionWidth) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 斑马线交替背景
    final bool isEven = index % 2 == 0;
    final rowBgColor = isEven 
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerLowest;

    // 计算全局序号
    final absoluteIndex = (_currentPage - 1) * _pageSize + index + 1;

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
          ..._columns.map((col) {
            final colWidth = _columnWidths[col] ?? 120.0;
            final cellValue = row[col];
            final cellStr = _formatCellValue(cellValue);

            return GestureDetector(
              onDoubleTap: () => _showCellDetail(col, cellValue),
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
              onPressed: () => _deleteRow(row),
              tooltip: '删除此行',
            ),
          ),
        ],
      ),
    );
  }

  // 5. 底部翻页控制器 UI
  Widget _buildPaginationFooter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final totalPages = max(1, (_totalRows / _pageSize).ceil());
    final isFirstPage = _currentPage == 1;
    final isLastPage = _currentPage == totalPages;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // 左侧：条数摘要
          Text(
            '共 $_totalRows 行  显示第 ${min((_currentPage - 1) * _pageSize + 1, _totalRows)} - ${min(_currentPage * _pageSize, _totalRows)} 行',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          
          const Spacer(),

          // 中间：翻页控制
          IconButton(
            icon: const Icon(Icons.first_page, size: 18),
            onPressed: isFirstPage
                ? null
                : () {
                    setState(() => _currentPage = 1);
                    _loadPageData();
                  },
            tooltip: '首页',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: isFirstPage
                ? null
                : () {
                    setState(() => _currentPage--);
                    _loadPageData();
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
                    controller: _pageJumpController,
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
                        setState(() => _currentPage = targetPage);
                        _loadPageData();
                      } else {
                        _pageJumpController.text = _currentPage.toString();
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
                    setState(() => _currentPage++);
                    _loadPageData();
                  },
            tooltip: '下一页',
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 18),
            onPressed: isLastPage
                ? null
                : () {
                    setState(() => _currentPage = totalPages);
                    _loadPageData();
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
                value: _pageSize,
                items: [50, 100, 200, 500, 1000].map((size) {
                  return DropdownMenuItem<int>(
                    value: size,
                    child: Text('$size 行', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _pageSize = val;
                      _currentPage = 1;
                    });
                    _loadPageData();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
