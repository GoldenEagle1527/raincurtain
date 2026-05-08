// scripts/utils.js
'use strict';

var Utils = (function () {

  var CATEGORY_ICONS = {
    '餐饮': 'restaurant',
    '购物': 'shopping_bag',
    '交通': 'directions_car',
    '住房': 'home',
    '娱乐': 'sports_esports',
    '医疗': 'local_hospital',
    '教育': 'school',
    '通讯': 'phone_android',
    '日用': 'inventory_2',
    '服饰': 'checkroom',
    '旅行': 'flight',
    '人情社交': 'people',
    '其他': 'more_horiz'
  };

  var CATEGORY_HUES = {
    '餐饮': 15,
    '购物': 330,
    '交通': 210,
    '住房': 30,
    '娱乐': 270,
    '医疗': 0,
    '教育': 45,
    '通讯': 190,
    '日用': 60,
    '服饰': 300,
    '旅行': 170,
    '人情社交': 240,
    '其他': 120
  };

  /** 生成唯一 ID */
  function generateId() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 9);
  }

  /** 时间戳 → "2026-05-07" */
  function formatDate(timestamp) {
    var d = new Date(timestamp);
    var y = d.getFullYear();
    var m = String(d.getMonth() + 1).padStart(2, '0');
    var day = String(d.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + day;
  }

  /** "2026-05-07" → "5月7日" */
  function formatDateDisplay(dateStr) {
    if (!dateStr) return '';
    var parts = dateStr.split('-');
    return parseInt(parts[1], 10) + '月' + parseInt(parts[2], 10) + '日';
  }

  /** 金额格式化（千分位 + 两位小数） */
  function formatCurrency(amount) {
    var n = Number(amount) || 0;
    return n.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  /** 获取某日所在周的起止日期 [start, end] */
  function getWeekRange(date) {
    var d = new Date(date);
    var day = d.getDay() || 7;
    var start = new Date(d);
    start.setDate(d.getDate() - day + 1);
    var end = new Date(start);
    end.setDate(start.getDate() + 6);
    return [formatDate(start.getTime()), formatDate(end.getTime())];
  }

  /** 获取某月的起止日期 [start, end] */
  function getMonthRange(date) {
    var d = new Date(date);
    var start = new Date(d.getFullYear(), d.getMonth(), 1);
    var end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    return [formatDate(start.getTime()), formatDate(end.getTime())];
  }

  /** 按日期分组记录 */
  function groupByDate(records) {
    var groups = {};
    records.forEach(function (r) {
      if (!groups[r.date]) groups[r.date] = [];
      groups[r.date].push(r);
    });
    return groups;
  }

  /** 按分类分组并求和 */
  function groupByCategory(records) {
    var groups = {};
    records.forEach(function (r) {
      if (!groups[r.category]) groups[r.category] = 0;
      groups[r.category] += r.amount;
    });
    return groups;
  }

  /** 按日期范围筛选 */
  function filterByDateRange(records, start, end) {
    return records.filter(function (r) {
      return r.date >= start && r.date <= end;
    });
  }

  /** 判断是否是今天 */
  function isToday(dateStr) {
    return dateStr === formatDate(Date.now());
  }

  /** 获取分类图标名 */
  function getCategoryIcon(category) {
    return CATEGORY_ICONS[category] || 'more_horiz';
  }

  /** 获取分类色相值 */
  function getCategoryHue(category) {
    return CATEGORY_HUES[category] !== undefined ? CATEGORY_HUES[category] : 120;
  }

  return {
    CATEGORY_ICONS: CATEGORY_ICONS,
    CATEGORY_HUES: CATEGORY_HUES,
    generateId: generateId,
    formatDate: formatDate,
    formatDateDisplay: formatDateDisplay,
    formatCurrency: formatCurrency,
    getWeekRange: getWeekRange,
    getMonthRange: getMonthRange,
    groupByDate: groupByDate,
    groupByCategory: groupByCategory,
    filterByDateRange: filterByDateRange,
    isToday: isToday,
    getCategoryIcon: getCategoryIcon,
    getCategoryHue: getCategoryHue
  };

})();
