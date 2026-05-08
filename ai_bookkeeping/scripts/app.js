// scripts/app.js
'use strict';

(function () {

  // ---------- 页面刷新 ----------

  function refreshHome() {
    UI.renderWalletCard(AppState.getBalance());
    UI.renderTodayRecords(AppState.getTodayRecords(), handleDeleteRecord);
  }

  function refreshStats() {
    var s = AppState.get();
    var now = new Date();
    var range = getDateRange(s.statsGranularity, now);
    var records = AppState.getFilteredRecords('all', range[0], range[1]);
    UIStats.renderStatsSummary(records);
    ChartModule.renderPieChart('pie-chart', records, s.statsType);
    ChartModule.renderLineChart('line-chart', records, s.statsGranularity);
  }

  function getDateRange(granularity, now) {
    if (granularity === 'day') {
      var today = Utils.formatDate(now.getTime());
      return [today, today];
    }
    if (granularity === 'week') return Utils.getWeekRange(now);
    return Utils.getMonthRange(now);
  }

  function refreshSettings() {
    UIStats.setSettingsBalanceValue(AppState.getBalance());
    UIStats.renderSettingsStats(
      AppState.getRecordCount(),
      AppState.getTotalExpense(),
      AppState.getTotalIncome()
    );
  }

  // ---------- AI 辅助填写 ----------

  async function handleAiSend() {
    var text = UI.getInputText();
    if (!text) { UI.showToast('请输入消费或收入描述'); return; }
    if (!Api.isConfigured()) { UI.showToast('请先在宿主设置中配置 API 密钥'); return; }

    UI.showAiLoadingModal();
    try {
      var parsed = await Api.parseExpense(text);
      UI.hideAiLoadingModal();
      UI.fillFormWithAiResult(parsed);
      UI.clearInputText();
      UI.showToast('AI 解析完成，请检查后提交');
    } catch (err) {
      UI.showAiErrorModal(err.message, function () { handleAiSend(); });
      console.error('Parse error:', err);
    }
  }

  // ---------- 语音输入 ----------

  // [DEBUG] 测试模式开关：true 时点击录音按钮不录音，直接用预置音频发送请求
  var VOICE_TEST_MODE = true;

  /**
   * [DEBUG] 生成一段模拟的 webm 音频 base64 数据。
   * 用合法的 webm (EBML) 文件头 + 伪造 payload，大小约 47KB（与真实录音接近），
   * 便于复现"包含 data: URI 的大请求体"场景。
   * 注意：这不是一段可解码的真实音频，服务端会返回解析错误，
   *       但网络请求本身应该能成功到达服务端。
   */
  function generateMockAudioBase64() {
    // 合法的 webm EBML 文件头字节（前 32 字节来自真实 webm 文件）
    var headerBytes = [
      0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81,
      0x01, 0x42, 0xF7, 0x81, 0x01, 0x42, 0xF2, 0x81,
      0x04, 0x42, 0xF3, 0x81, 0x08, 0x42, 0x82, 0x84,
      0x77, 0x65, 0x62, 0x6D, 0x42, 0x87, 0x81, 0x04
    ];
    // 目标大小约 47KB（与真实录音样本一致）
    var targetBytes = 47 * 1024;
    var bytes = new Uint8Array(targetBytes);
    for (var i = 0; i < headerBytes.length; i++) bytes[i] = headerBytes[i];
    // 用可重复模式填充 payload，让 base64 不全是 AAAA
    for (var j = headerBytes.length; j < targetBytes; j++) {
      bytes[j] = (j * 31 + 17) & 0xFF;
    }
    // 转 base64
    var binary = '';
    var chunkSize = 0x8000;
    for (var k = 0; k < bytes.length; k += chunkSize) {
      binary += String.fromCharCode.apply(null, bytes.subarray(k, k + chunkSize));
    }
    return btoa(binary);
  }

  async function handleVoiceToggle() {
    // [DEBUG] 测试模式：直接用预置音频发送请求，跳过真实录音
    if (VOICE_TEST_MODE) {
      if (!Api.isConfigured()) {
        UI.showToast('请先在宿主设置中配置 API 密钥');
        return;
      }
      console.log('[Voice][TEST] 使用模拟音频数据，跳过录音');
      UI.showAiLoadingModal('[测试] 语音识别中...');
      var mockBase64 = generateMockAudioBase64();
      console.log('[Voice][TEST] 模拟音频 base64 长度:', mockBase64.length);
      try {
        var parsed = await Api.parseVoiceAudio(mockBase64, 'audio/webm;codecs=opus');
        UI.hideAiLoadingModal();
        UI.fillFormWithAiResult(parsed);
        UI.showToast('[测试] 语音解析完成');
      } catch (err) {
        UI.showAiErrorModal('[测试] 语音解析失败:\n' + err.message);
        console.error('[Voice][TEST] parse error:', err);
      }
      return;
    }

    if (!Voice.isSupported()) {
      UI.showToast('当前环境不支持录音');
      return;
    }
    if (!Api.isConfigured()) {
      UI.showToast('请先在宿主设置中配置 API 密钥');
      return;
    }

    if (Voice.getIsRecording()) {
      handleVoiceStop();
    } else {
      handleVoiceStart();
    }
  }

  async function handleVoiceStart() {
    try {
      await Voice.startRecording();
      UI.setVoiceRecording(true);
    } catch (err) {
      UI.showToast('无法启动录音: ' + err.message);
      console.error('Voice start error:', err);
    }
  }

  async function handleVoiceStop() {
    UI.setVoiceRecording(false);
    UI.showAiLoadingModal('正在处理录音...');

    var audioBlob;
    try {
      audioBlob = await Voice.stopRecording();
    } catch (err) {
      UI.showAiErrorModal('录音停止失败: ' + err.message);
      console.error('Voice stop error:', err);
      return;
    }

    console.log('[Voice] 录音完成:', {
      type: audioBlob.type,
      sizeKB: Math.round(audioBlob.size / 1024)
    });

    if (audioBlob.size < 1000) {
      UI.showAiErrorModal('录音时间太短，请重新录制');
      return;
    }

    UI.showAiLoadingModal('语音识别中...');

    var base64;
    try {
      base64 = await Voice.blobToBase64(audioBlob);
    } catch (err) {
      UI.showAiErrorModal('音频编码失败: ' + err.message);
      console.error('Base64 encode error:', err);
      return;
    }

    try {
      var parsed = await Api.parseVoiceAudio(base64, audioBlob.type);
      UI.hideAiLoadingModal();
      UI.fillFormWithAiResult(parsed);
      UI.showToast('语音解析完成，请检查后提交');
    } catch (err) {
      UI.showAiErrorModal('语音解析失败:\n' + err.message);
      console.error('Voice parse error:', err);
    }
  }

  // ---------- 手动/提交记账 ----------

  async function handleSubmit() {
    var formData = UI.getFormData();

    // 校验必填字段
    if (!formData.item) { UI.showToast('请输入项目名'); return; }
    if (!formData.amount || formData.amount <= 0) { UI.showToast('请输入有效的金额'); return; }

    var now = Date.now();
    var record = {
      id: Utils.generateId(),
      type: AppState.get().inputType,
      item: formData.item,
      category: formData.category,
      amount: formData.amount,
      note: formData.note,
      timestamp: now,
      date: Utils.formatDate(now)
    };

    AppState.addRecord(record);
    UI.clearForm();

    var saveOk = true;
    try {
      await Api.saveRecords(JSON.parse(JSON.stringify(AppState.get().records)));
    } catch (err) { console.error('Failed to save records:', err); saveOk = false; }
    try {
      await Api.saveWalletBalance(AppState.getBalance());
    } catch (err) { console.error('Failed to save wallet balance:', err); saveOk = false; }
    try {
      await Api.emitLastRecord(record);
    } catch (err) { console.error('Failed to emit last record:', err); }

    refreshHome();
    UI.showToast(saveOk ? '记账成功' : '记账成功，但数据保存可能失败');
  }

  // ---------- 删除记录 ----------

  async function handleDeleteRecord(id) {
    if (!AppState.removeRecord(id)) return;
    try {
      await Api.saveRecords(JSON.parse(JSON.stringify(AppState.get().records)));
    } catch (err) { console.error('Failed to save records after delete:', err); }
    try {
      await Api.saveWalletBalance(AppState.getBalance());
    } catch (err) { console.error('Failed to save wallet balance after delete:', err); }
    refreshHome();
    UI.showToast('已删除');
  }

  // ---------- Tab / 筛选 ----------

  function handleTabSwitch(tab) {
    AppState.switchTab(tab);
    UI.activateTab(tab);
    if (tab === 'home') refreshHome();
    if (tab === 'stats') refreshStats();
    if (tab === 'settings') refreshSettings();
  }

  function handleTypeSwitch(type) {
    AppState.setInputType(type);
    UI.updateInputType(type);
  }

  function handleGranularitySwitch(g) {
    AppState.setStatsGranularity(g);
    refreshStats();
  }

  function handleStatsTypeSwitch(type) {
    AppState.setStatsType(type);
    refreshStats();
  }

  // ---------- 设置 ----------

  async function handleSaveBalance() {
    var val = UIStats.getSettingsBalanceValue();
    var amount = parseFloat(val);
    if (isNaN(amount)) { UI.showToast('请输入有效的金额'); return; }
    AppState.setWalletBalance(amount);
    try { await Api.saveWalletBalance(amount); }
    catch (err) { console.error('Failed to save balance:', err); }
    UI.showToast('余额已保存');
    refreshHome();
  }

  async function handleClearData() {
    if (!confirm('确定要清除所有记录吗？此操作不可撤销。')) return;
    AppState.setRecords([]);
    AppState.setWalletBalance(0);
    try { await Api.saveRecords([]); }
    catch (err) { console.error('Failed to clear records:', err); }
    try { await Api.saveWalletBalance(0); }
    catch (err) { console.error('Failed to reset balance:', err); }
    refreshHome();
    refreshSettings();
    UI.showToast('所有记录已清除');
  }

  // ---------- 初始化 ----------

  async function init() {
    try { await Api.loadConfig(); }
    catch (e) { console.error('Config load error:', e); }

    try {
      var balance = await Api.loadWalletBalance();
      AppState.setWalletBalance(balance);
    } catch (err) { console.error('Failed to load wallet balance:', err); }
    try {
      var records = await Api.loadRecords();
      AppState.setRecords(records);
    } catch (err) { console.error('Failed to load records:', err); }

    UI.initCategorySelect();
    refreshHome();

    UIStats.bindEvents({
      onTabSwitch: handleTabSwitch,
      onAiSend: handleAiSend,
      onVoiceToggle: handleVoiceToggle,
      onSubmit: handleSubmit,
      onTypeSwitch: handleTypeSwitch,
      onGranularitySwitch: handleGranularitySwitch,
      onStatsTypeSwitch: handleStatsTypeSwitch,
      onSaveBalance: handleSaveBalance,
      onClearData: handleClearData
    });
  }

  init();

})();
