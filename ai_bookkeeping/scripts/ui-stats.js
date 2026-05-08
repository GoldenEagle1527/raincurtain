// scripts/ui-stats.js
'use strict';

var UIStats = (function () {

  var elements = {
    statsSummary: document.getElementById('stats-summary'),
    settingsBalance: document.getElementById('settings-balance'),
    settingsStats: document.getElementById('settings-stats')
  };

  // ---------- 统计页汇总 ----------

  function renderStatsSummary(records) {
    elements.statsSummary.innerHTML = '';
    var totalExpense = 0;
    var totalIncome = 0;
    var count = records.length;
    records.forEach(function (r) {
      if (r.type === 'expense') totalExpense += r.amount;
      else totalIncome += r.amount;
    });

    var items = [
      { label: '总支出', value: '¥' + Utils.formatCurrency(totalExpense) },
      { label: '总收入', value: '¥' + Utils.formatCurrency(totalIncome) },
      { label: '笔数', value: count + '笔' }
    ];

    items.forEach(function (it) {
      var div = document.createElement('div');
      div.className = 'stats-summary__item';
      var label = document.createElement('div');
      label.className = 'stats-summary__label';
      label.textContent = it.label;
      var val = document.createElement('div');
      val.className = 'stats-summary__value';
      val.textContent = it.value;
      div.appendChild(label);
      div.appendChild(val);
      elements.statsSummary.appendChild(div);
    });
  }

  // ---------- 设置页数据概览 ----------

  function renderSettingsStats(recordCount, totalExpense, totalIncome) {
    elements.settingsStats.innerHTML = '';
    var items = [
      { label: '总记录', value: recordCount + '笔' },
      { label: '总支出', value: '¥' + Utils.formatCurrency(totalExpense) },
      { label: '总收入', value: '¥' + Utils.formatCurrency(totalIncome) },
      { label: '净收支', value: '¥' + Utils.formatCurrency(totalIncome - totalExpense) }
    ];
    items.forEach(function (it) {
      var div = document.createElement('div');
      div.className = 'settings-stats__item';
      var label = document.createElement('div');
      label.className = 'settings-stats__label';
      label.textContent = it.label;
      var val = document.createElement('div');
      val.className = 'settings-stats__value';
      val.textContent = it.value;
      div.appendChild(label);
      div.appendChild(val);
      elements.settingsStats.appendChild(div);
    });
  }

  // ---------- 设置页余额输入 ----------

  function getSettingsBalanceValue() {
    return elements.settingsBalance.value;
  }

  function setSettingsBalanceValue(val) {
    elements.settingsBalance.value = val;
  }

  // ---------- 事件绑定 ----------

  function bindEvents(handlers) {
    // Tab 切换
    document.querySelectorAll('.tab-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        handlers.onTabSwitch(btn.getAttribute('data-tab'));
      });
    });

    // AI 发送按钮
    document.getElementById('btn-ai-send')
      .addEventListener('click', handlers.onAiSend);

    // 语音输入按钮
    document.getElementById('btn-voice')
      .addEventListener('click', handlers.onVoiceToggle);

    // AI 输入框回车
    document.getElementById('ai-input')
      .addEventListener('keydown', function (e) {
        if (e.key === 'Enter') {
          e.preventDefault();
          handlers.onAiSend();
        }
      });

    // 记账提交按钮
    document.getElementById('btn-submit')
      .addEventListener('click', handlers.onSubmit);

    // 模态框关闭按钮
    document.getElementById('modal-close-btn')
      .addEventListener('click', function () {
        UI.hideAiLoadingModal();
      });

    // 输入类型切换
    document.querySelectorAll('[data-type]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        handlers.onTypeSwitch(btn.getAttribute('data-type'));
      });
    });

    // 统计粒度切换
    document.querySelectorAll('[data-granularity]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        handlers.onGranularitySwitch(btn.getAttribute('data-granularity'));
        document.querySelectorAll('[data-granularity]').forEach(function (b) {
          b.classList.toggle('is-active',
            b.getAttribute('data-granularity') === btn.getAttribute('data-granularity'));
        });
      });
    });

    // 统计类型切换
    document.querySelectorAll('[data-stype]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        handlers.onStatsTypeSwitch(btn.getAttribute('data-stype'));
        document.querySelectorAll('[data-stype]').forEach(function (b) {
          b.classList.toggle('is-active',
            b.getAttribute('data-stype') === btn.getAttribute('data-stype'));
        });
      });
    });

    // 保存余额
    document.getElementById('btn-save-balance')
      .addEventListener('click', handlers.onSaveBalance);

    // 清除数据
    document.getElementById('btn-clear-data')
      .addEventListener('click', handlers.onClearData);
  }

  return {
    renderStatsSummary: renderStatsSummary,
    renderSettingsStats: renderSettingsStats,
    getSettingsBalanceValue: getSettingsBalanceValue,
    setSettingsBalanceValue: setSettingsBalanceValue,
    bindEvents: bindEvents
  };

})();
