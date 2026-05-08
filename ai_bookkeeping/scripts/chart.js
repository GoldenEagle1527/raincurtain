// scripts/chart.js
'use strict';

var ChartModule = (function () {

  var pieInstance = null;
  var lineInstance = null;

  /** 从 MD3 CSS 变量读取颜色 */
  function getMd3Color(varName) {
    return getComputedStyle(document.documentElement).getPropertyValue(varName).trim();
  }

  /** 根据分类色相生成 HSL 颜色 */
  function getCategoryColor(category, alpha) {
    var hue = Utils.getCategoryHue(category);
    if (alpha !== undefined) {
      return 'hsla(' + hue + ', 65%, 55%, ' + alpha + ')';
    }
    return 'hsl(' + hue + ', 65%, 55%)';
  }

  /** 将记录转换为饼图数据 */
  function preparePieData(records, type) {
    var filtered = records.filter(function (r) { return r.type === type; });
    var grouped = Utils.groupByCategory(filtered);
    var labels = [];
    var data = [];
    var colors = [];
    Object.keys(grouped).sort(function (a, b) {
      return grouped[b] - grouped[a];
    }).forEach(function (cat) {
      labels.push(cat);
      data.push(grouped[cat]);
      colors.push(getCategoryColor(cat));
    });
    return { labels: labels, data: data, colors: colors };
  }

  /** 将记录转换为折线图数据 */
  function prepareLineData(records, granularity) {
    var grouped = {};
    records.forEach(function (r) {
      var key = getGroupKey(r.date, granularity);
      if (!grouped[key]) grouped[key] = { expense: 0, income: 0 };
      if (r.type === 'expense') {
        grouped[key].expense += r.amount;
      } else {
        grouped[key].income += r.amount;
      }
    });
    var keys = Object.keys(grouped).sort();
    return {
      labels: keys.map(function (k) { return formatGroupLabel(k, granularity); }),
      expense: keys.map(function (k) { return grouped[k].expense; }),
      income: keys.map(function (k) { return grouped[k].income; })
    };
  }

  /** 获取分组键 */
  function getGroupKey(dateStr, granularity) {
    if (granularity === 'day') return dateStr;
    if (granularity === 'week') return Utils.getWeekRange(dateStr)[0];
    return dateStr.slice(0, 7);
  }

  /** 格式化分组标签 */
  function formatGroupLabel(key, granularity) {
    if (granularity === 'day') return Utils.formatDateDisplay(key);
    if (granularity === 'week') return Utils.formatDateDisplay(key) + '周';
    var parts = key.split('-');
    return parseInt(parts[1], 10) + '月';
  }

  /** 获取通用 Chart.js 默认配置 */
  function getDefaultOptions() {
    var textColor = getMd3Color('--md-on-surface') || '#333';
    return {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: textColor, font: { size: 12 } }
        }
      }
    };
  }

  /** 渲染饼图 */
  function renderPieChart(canvasId, records, type) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return;
    if (pieInstance) pieInstance.destroy();

    var pieData = preparePieData(records, type);
    if (pieData.data.length === 0) {
      pieInstance = null;
      clearCanvas(canvas);
      return;
    }

    var opts = getDefaultOptions();
    opts.plugins.legend.position = 'right';

    pieInstance = new Chart(canvas, {
      type: 'doughnut',
      data: {
        labels: pieData.labels,
        datasets: [{
          data: pieData.data,
          backgroundColor: pieData.colors,
          borderWidth: 2,
          borderColor: getMd3Color('--md-surface-container') || '#fff'
        }]
      },
      options: opts
    });
  }

  /** 渲染折线图 */
  function renderLineChart(canvasId, records, granularity) {
    var canvas = document.getElementById(canvasId);
    if (!canvas) return;
    if (lineInstance) lineInstance.destroy();

    var lineData = prepareLineData(records, granularity);
    if (lineData.labels.length === 0) {
      lineInstance = null;
      clearCanvas(canvas);
      return;
    }

    var textColor = getMd3Color('--md-on-surface') || '#333';
    var gridColor = getMd3Color('--md-outline-variant') || '#e0e0e0';
    var opts = getDefaultOptions();
    opts.scales = {
      x: { ticks: { color: textColor, font: { size: 11 } }, grid: { color: gridColor } },
      y: { ticks: { color: textColor, font: { size: 11 } }, grid: { color: gridColor }, beginAtZero: true }
    };

    lineInstance = new Chart(canvas, {
      type: 'line',
      data: {
        labels: lineData.labels,
        datasets: [
          {
            label: '支出',
            data: lineData.expense,
            borderColor: getMd3Color('--md-error') || '#e53935',
            backgroundColor: 'transparent',
            tension: 0.3,
            pointRadius: 3
          },
          {
            label: '收入',
            data: lineData.income,
            borderColor: getMd3Color('--md-success') || '#43a047',
            backgroundColor: 'transparent',
            tension: 0.3,
            pointRadius: 3
          }
        ]
      },
      options: opts
    });
  }

  /** 清空画布 */
  function clearCanvas(canvas) {
    var ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  return {
    renderPieChart: renderPieChart,
    renderLineChart: renderLineChart,
    getCategoryColor: getCategoryColor
  };

})();
