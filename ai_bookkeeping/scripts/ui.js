// scripts/ui.js
'use strict';

var UI = (function () {

  var TOAST_DURATION = 2000;
  var TOAST_FADE_OUT = 300;

  var elements = {
    walletAmount: document.getElementById('wallet-amount'),
    formItem: document.getElementById('form-item'),
    formAmount: document.getElementById('form-amount'),
    formCategory: document.getElementById('form-category'),
    formNote: document.getElementById('form-note'),
    aiInput: document.getElementById('ai-input'),
    aiLoadingModal: document.getElementById('ai-loading-modal'),
    modalText: document.getElementById('modal-text'),
    modalActions: document.getElementById('modal-actions'),
    modalCloseBtn: document.getElementById('modal-close-btn'),
    modalRetryBtn: document.getElementById('modal-retry-btn'),
    todaySummary: document.getElementById('today-summary'),
    todayRecords: document.getElementById('today-records'),
    toastContainer: document.getElementById('toast-container')
  };

  /** 创建带类名和文本的元素 */
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function showToast(message) {
    var toast = el('div', 'toast', message);
    elements.toastContainer.appendChild(toast);
    requestAnimationFrame(function () { toast.classList.add('is-show'); });
    setTimeout(function () {
      toast.classList.remove('is-show');
      setTimeout(function () {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, TOAST_FADE_OUT);
    }, TOAST_DURATION);
  }

  function activateTab(tab) {
    document.querySelectorAll('.tab-btn').forEach(function (btn) {
      btn.classList.toggle('is-active', btn.getAttribute('data-tab') === tab);
    });
    document.querySelectorAll('.page').forEach(function (page) {
      page.classList.toggle('is-active', page.id === 'page-' + tab);
    });
    // 表单只在首页显示
    var inputBar = document.querySelector('.input-bar');
    if (inputBar) {
      inputBar.classList.toggle('hidden', tab !== 'home');
    }
  }

  function renderWalletCard(balance) {
    elements.walletAmount.textContent = '¥' + Utils.formatCurrency(balance);
  }

  // ---------- 模态框 ----------

  /** 当前重试回调（用于清理事件监听） */
  var _currentRetryHandler = null;

  function showAiLoadingModal(text) {
    var modal = elements.aiLoadingModal;
    var dots = modal.querySelector('.loading-dots');
    if (dots) dots.classList.remove('hidden');
    elements.modalText.textContent = text || 'AI 正在解析...';
    elements.modalActions.classList.add('hidden');
    _cleanupRetryHandler();
    modal.classList.remove('hidden');
  }

  function hideAiLoadingModal() {
    elements.aiLoadingModal.classList.add('hidden');
    _cleanupRetryHandler();
  }

  function showAiErrorModal(message, onRetry) {
    var modal = elements.aiLoadingModal;
    var dots = modal.querySelector('.loading-dots');
    if (dots) dots.classList.add('hidden');
    elements.modalText.textContent = message || '解析失败';
    elements.modalActions.classList.remove('hidden');

    // 设置重试按钮
    _cleanupRetryHandler();
    if (onRetry && typeof onRetry === 'function') {
      elements.modalRetryBtn.classList.remove('hidden');
      _currentRetryHandler = function () {
        hideAiLoadingModal();
        onRetry();
      };
      elements.modalRetryBtn.addEventListener('click', _currentRetryHandler);
    } else {
      elements.modalRetryBtn.classList.add('hidden');
    }

    modal.classList.remove('hidden');
  }

  /** 清理重试按钮的事件监听 */
  function _cleanupRetryHandler() {
    if (_currentRetryHandler) {
      elements.modalRetryBtn.removeEventListener('click', _currentRetryHandler);
      _currentRetryHandler = null;
    }
  }

  // ---------- 表单操作 ----------

  /** 初始化分类下拉框选项 */
  function initCategorySelect() {
    var select = elements.formCategory;
    select.innerHTML = '';
    var categories = Object.keys(Utils.CATEGORY_ICONS);
    categories.forEach(function (cat) {
      var option = document.createElement('option');
      option.value = cat;
      option.textContent = cat;
      select.appendChild(option);
    });
  }

  /** 将 AI 解析结果回填到表单 */
  function fillFormWithAiResult(parsed) {
    if (parsed.item) elements.formItem.value = parsed.item;
    if (parsed.amount !== undefined) elements.formAmount.value = parsed.amount;
    if (parsed.category) elements.formCategory.value = parsed.category;
    if (parsed.note) elements.formNote.value = parsed.note;
    if (parsed.type) {
      AppState.setInputType(parsed.type);
      updateInputType(parsed.type);
    }
  }

  /** 读取表单数据 */
  function getFormData() {
    return {
      item: elements.formItem.value.trim(),
      amount: parseFloat(elements.formAmount.value) || 0,
      category: elements.formCategory.value,
      note: elements.formNote.value.trim()
    };
  }

  /** 清空表单 */
  function clearForm() {
    elements.formItem.value = '';
    elements.formAmount.value = '';
    elements.formCategory.selectedIndex = 0;
    elements.formNote.value = '';
  }

  // ---------- 记录列表 ----------

  function renderTodayRecords(records, onDelete) {
    elements.todayRecords.innerHTML = '';
    if (records.length === 0) {
      var empty = el('div', 'empty-state');
      empty.appendChild(el('span', 'material-icons empty-state__icon', 'receipt_long'));
      empty.appendChild(el('div', 'empty-state__text', '今天还没有记录'));
      elements.todayRecords.appendChild(empty);
      elements.todaySummary.textContent = '';
      return;
    }
    updateTodaySummary(records);
    records.forEach(function (r) {
      elements.todayRecords.appendChild(createRecordItem(r, onDelete));
    });
  }

  function updateTodaySummary(records) {
    var exp = 0, inc = 0;
    records.forEach(function (r) {
      if (r.type === 'expense') exp += r.amount; else inc += r.amount;
    });
    var parts = [];
    if (exp > 0) parts.push('支出 ¥' + Utils.formatCurrency(exp));
    if (inc > 0) parts.push('收入 ¥' + Utils.formatCurrency(inc));
    elements.todaySummary.textContent = parts.join(' | ');
  }

  function createRecordItem(record, onDelete) {
    var item = el('div', 'record-item');
    item.appendChild(el('span', 'material-icons record-item__icon', Utils.getCategoryIcon(record.category)));
    var info = el('div', 'record-item__info');
    info.appendChild(el('div', 'record-item__name', record.item));
    if (record.note) info.appendChild(el('div', 'record-item__note', record.note));
    item.appendChild(info);
    var amountEl = el('span', 'record-item__amount');
    var isExpense = record.type === 'expense';
    amountEl.classList.add(isExpense ? 'record-item__amount--expense' : 'record-item__amount--income');
    amountEl.textContent = (isExpense ? '-¥' : '+¥') + Utils.formatCurrency(record.amount);
    item.appendChild(amountEl);
    var delBtn = el('button', 'btn btn--icon');
    var delIcon = el('span', 'material-icons', 'close');
    delIcon.style.cssText = 'font-size:18px;opacity:0.5';
    delBtn.appendChild(delIcon);
    delBtn.addEventListener('click', function () { onDelete(record.id); });
    item.appendChild(delBtn);
    return item;
  }

  function updateInputType(type) {
    document.getElementById('type-expense').classList.toggle('is-active', type === 'expense');
    document.getElementById('type-income').classList.toggle('is-active', type === 'income');
  }

  function getInputText() { return elements.aiInput.value.trim(); }
  function clearInputText() { elements.aiInput.value = ''; }
  function setInputText(text) { elements.aiInput.value = text; }

  /** 设置语音按钮的录音状态 */
  function setVoiceRecording(recording) {
    var btn = document.getElementById('btn-voice');
    if (!btn) return;
    var icon = btn.querySelector('.material-icons');
    if (recording) {
      btn.classList.add('is-recording');
      if (icon) icon.textContent = 'stop';
      btn.title = '停止录音';
    } else {
      btn.classList.remove('is-recording');
      if (icon) icon.textContent = 'mic';
      btn.title = '语音输入';
    }
  }

  return {
    showToast: showToast,
    activateTab: activateTab,
    renderWalletCard: renderWalletCard,
    showAiLoadingModal: showAiLoadingModal,
    hideAiLoadingModal: hideAiLoadingModal,
    showAiErrorModal: showAiErrorModal,
    initCategorySelect: initCategorySelect,
    fillFormWithAiResult: fillFormWithAiResult,
    getFormData: getFormData,
    clearForm: clearForm,
    renderTodayRecords: renderTodayRecords,
    updateInputType: updateInputType,
    getInputText: getInputText,
    clearInputText: clearInputText,
    setInputText: setInputText,
    setVoiceRecording: setVoiceRecording
  };

})();
