import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/plugin_storage_manager.dart';

class PluginDataController extends ChangeNotifier {
  final String pluginId;
  final String pluginName;
  final PluginStorageManager storageManager;

  PluginDataController({
    required this.pluginId,
    required this.pluginName,
    required this.storageManager,
  }) {
    loadTables();
  }

  // 表格状态
  List<String> tableNames = [];
  String? selectedTable;
  bool isLoadingTables = true;
  String tableSearchQuery = '';

  // 每个表行数的缓存 (tableName -> rowCount)
  final Map<String, int> tableRowCounts = {};

  // 当前选中表的数据状态
  List<Map<String, dynamic>> pageData = [];
  List<String> columns = [];
  Map<String, double> columnWidths = {};
  bool isLoadingData = false;
  String? dataLoadError;

  // 分页状态
  int currentPage = 1;
  int pageSize = 100;
  int totalRows = 0;

  // 过滤状态
  String? filterColumn;
  final TextEditingController filterValController = TextEditingController();
  Map<String, dynamic>? activeWhereClause;

  // 手机端自适应导航状态
  String? selectedTableForMobile;

  // 页码跳转输入框
  final TextEditingController pageJumpController = TextEditingController();

  // 滚动控制器
  final ScrollController horizontalScrollController = ScrollController();
  final ScrollController verticalScrollController = ScrollController();

  @override
  void dispose() {
    filterValController.dispose();
    pageJumpController.dispose();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    super.dispose();
  }

  // 1. 加载表列表及各表行数
  Future<void> loadTables() async {
    isLoadingTables = true;
    notifyListeners();

    try {
      final tables = await storageManager.getShortTableNames(pluginId);
      
      tableRowCounts.clear();
      for (final table in tables) {
        final count = await storageManager.count(pluginId, table, null);
        tableRowCounts[table] = count;
      }

      tableNames = tables;
      isLoadingTables = false;
      
      // 默认选中第一个表
      if (tables.isNotEmpty && selectedTable == null) {
        selectTable(tables.first);
      } else {
        notifyListeners();
      }
    } catch (e) {
      isLoadingTables = false;
      notifyListeners();
      rethrow;
    }
  }

  // 切换选中表
  void selectTable(String tableName) {
    selectedTable = tableName;
    selectedTableForMobile = tableName;
    currentPage = 1;
    pageJumpController.text = '1';
    // 重置过滤
    filterColumn = null;
    filterValController.clear();
    activeWhereClause = null;
    notifyListeners();

    // 异步重置滚动条位置
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (horizontalScrollController.hasClients) {
        horizontalScrollController.jumpTo(0.0);
      }
      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(0.0);
      }
    });

    loadPageData();
  }

  // 2. 加载当前页的数据
  Future<void> loadPageData() async {
    final tableName = selectedTable;
    if (tableName == null) return;

    isLoadingData = true;
    dataLoadError = null;
    notifyListeners();

    try {
      // 查出该过滤条件下的总行数
      final total = await storageManager.count(
        pluginId,
        tableName,
        activeWhereClause,
      );

      // 查询分页数据
      final offset = (currentPage - 1) * pageSize;
      final rows = await storageManager.query(
        pluginId,
        tableName,
        where: activeWhereClause,
        limit: pageSize,
        offset: offset,
        orderBy: '_id DESC',
      );

      // 提取列名
      final colSet = <String>{'_id'};
      for (final row in rows) {
        colSet.addAll(row.keys);
      }
      final columnsList = colSet.toList();

      // 动态计算列宽
      final widths = _calculateColumnWidths(rows, columnsList);

      totalRows = total;
      pageData = rows;
      columns = columnsList;
      columnWidths = widths;
      isLoadingData = false;
      pageJumpController.text = currentPage.toString();
      
      // 更新左侧列表该表的实时总行数
      if (activeWhereClause == null) {
        tableRowCounts[tableName] = total;
      }
      notifyListeners();
    } catch (e) {
      pageData = [];
      columns = [];
      columnWidths = {};
      totalRows = 0;
      isLoadingData = false;
      dataLoadError = e.toString();
      notifyListeners();
    }
  }

  // 实时自适应列宽算法
  Map<String, double> _calculateColumnWidths(
      List<Map<String, dynamic>> rows, List<String> columns) {
    final widths = <String, double>{};
    for (final col in columns) {
      if (col == '_id') {
        widths[col] = 75.0;
        continue;
      }
      
      double maxLen = col.length.toDouble();
      for (final row in rows) {
        final val = row[col];
        if (val != null) {
          final strVal = formatCellValue(val);
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
      
      widths[col] = (45.0 + maxLen * 7.5).clamp(120.0, 360.0);
    }
    return widths;
  }

  // 格式化展示单元格
  String formatCellValue(dynamic val) {
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

  // 执行过滤筛选
  void applyFilter() {
    final col = filterColumn;
    final val = filterValController.text.trim();

    if (col == null || val.isEmpty) {
      activeWhereClause = null;
      currentPage = 1;
    } else {
      dynamic queryVal = val;
      final numVal = num.tryParse(val);
      if (numVal != null) {
        queryVal = numVal;
      } else if (val.toLowerCase() == 'true') {
        queryVal = 1;
      } else if (val.toLowerCase() == 'false') {
        queryVal = 0;
      }
      
      activeWhereClause = {col: queryVal};
      currentPage = 1;
    }
    notifyListeners();
    loadPageData();
  }

  // 清除过滤
  void clearFilter() {
    filterValController.clear();
    activeWhereClause = null;
    currentPage = 1;
    notifyListeners();
    loadPageData();
  }

  // 设置过滤列
  void setFilterColumn(String? col) {
    filterColumn = col;
    notifyListeners();
  }

  // 设置页大小
  void setPageSize(int size) {
    pageSize = size;
    currentPage = 1;
    notifyListeners();
    loadPageData();
  }

  // 设置当前页
  void setCurrentPage(int page) {
    currentPage = page;
    notifyListeners();
    loadPageData();
  }

  // 手机端返回列表
  void setMobileSelectedTableNull() {
    selectedTableForMobile = null;
    notifyListeners();
  }

  // 搜索框过滤表名
  void setTableSearchQuery(String query) {
    tableSearchQuery = query;
    notifyListeners();
  }

  // 删除单行
  Future<void> deleteRow(Map<String, dynamic> row) async {
    final tableName = selectedTable;
    if (tableName == null) return;
    final rowId = row['_id'];
    if (rowId == null) return;

    await storageManager.delete(
      pluginId,
      tableName,
      {'_id': rowId},
    );
    await loadTables(); // 同时刷新左侧统计
    await loadPageData();
  }

  // 清空整张表
  Future<void> clearTable() async {
    final tableName = selectedTable;
    if (tableName == null) return;

    await storageManager.clear(pluginId, tableName);
    currentPage = 1;
    await loadTables();
    await loadPageData();
  }

  // 导出全量 CSV
  Future<String?> generateCsvString() async {
    final tableName = selectedTable;
    if (tableName == null || columns.isEmpty) return null;

    final allRows = await storageManager.query(
      pluginId,
      tableName,
      where: activeWhereClause,
      orderBy: '_id DESC',
    );

    if (allRows.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.write('\uFEFF');
    
    // 表头
    buffer.writeln(columns.map((col) => '"${col.replaceAll('"', '""')}"').join(','));
    
    // 表行数据
    for (final row in allRows) {
      final rowCsv = columns.map((col) {
        final val = row[col];
        if (val == null) return '';
        final strVal = formatCellValue(val);
        return '"${strVal.replaceAll('"', '""')}"';
      }).join(',');
      buffer.writeln(rowCsv);
    }
    return buffer.toString();
  }
}
