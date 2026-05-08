// scripts/state.js
'use strict';

var AppState = (function () {

  var state = {
    records: [],
    walletBalance: 0,
    currentTab: 'home',
    isLoading: false,
    statsGranularity: 'month',
    statsType: 'expense',
    inputType: 'expense'
  };

  /** 获取状态快照 */
  function get() {
    return state;
  }

  /** 添加记录并更新余额 */
  function addRecord(record) {
    state.records.unshift(record);
    if (record.type === 'expense') {
      state.walletBalance -= record.amount;
    } else {
      state.walletBalance += record.amount;
    }
  }

  /** 删除记录并回退余额 */
  function removeRecord(id) {
    var idx = state.records.findIndex(function (r) { return r.id === id; });
    if (idx < 0) return false;
    var record = state.records[idx];
    if (record.type === 'expense') {
      state.walletBalance += record.amount;
    } else {
      state.walletBalance -= record.amount;
    }
    state.records.splice(idx, 1);
    return true;
  }

  /** 设置钱包余额 */
  function setWalletBalance(amount) {
    state.walletBalance = Number(amount) || 0;
  }

  /** 设置加载状态 */
  function setLoading(bool) {
    state.isLoading = bool;
  }

  /** 切换 Tab */
  function switchTab(tab) {
    state.currentTab = tab;
  }

  /** 设置统计粒度 */
  function setStatsGranularity(g) {
    state.statsGranularity = g;
  }

  /** 设置统计类型 */
  function setStatsType(type) {
    state.statsType = type;
  }

  /** 设置输入类型 */
  function setInputType(type) {
    state.inputType = type;
  }

  /** 初始化记录列表 */
  function setRecords(records) {
    state.records = records || [];
  }

  /** 获取当前余额 */
  function getBalance() {
    return state.walletBalance;
  }

  /** 获取今日记录 */
  function getTodayRecords() {
    var today = Utils.formatDate(Date.now());
    return state.records.filter(function (r) { return r.date === today; });
  }

  /** 获取筛选后的记录 */
  function getFilteredRecords(type, startDate, endDate) {
    return state.records.filter(function (r) {
      var matchType = type === 'all' || r.type === type;
      var matchDate = (!startDate || r.date >= startDate) && (!endDate || r.date <= endDate);
      return matchType && matchDate;
    });
  }

  /** 获取所有记录总数 */
  function getRecordCount() {
    return state.records.length;
  }

  /** 获取总支出 */
  function getTotalExpense() {
    return state.records.reduce(function (sum, r) {
      return r.type === 'expense' ? sum + r.amount : sum;
    }, 0);
  }

  /** 获取总收入 */
  function getTotalIncome() {
    return state.records.reduce(function (sum, r) {
      return r.type === 'income' ? sum + r.amount : sum;
    }, 0);
  }

  return {
    get: get,
    addRecord: addRecord,
    removeRecord: removeRecord,
    setWalletBalance: setWalletBalance,
    setLoading: setLoading,
    switchTab: switchTab,
    setStatsGranularity: setStatsGranularity,
    setStatsType: setStatsType,
    setInputType: setInputType,
    setRecords: setRecords,
    getBalance: getBalance,
    getTodayRecords: getTodayRecords,
    getFilteredRecords: getFilteredRecords,
    getRecordCount: getRecordCount,
    getTotalExpense: getTotalExpense,
    getTotalIncome: getTotalIncome
  };

})();
