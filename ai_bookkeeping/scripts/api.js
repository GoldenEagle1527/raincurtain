// scripts/api.js
'use strict';

var Api = (function () {

  var config = {
    apiKey: '',
    baseUrl: 'https://api.openai.com',
    model: 'gpt-4o-mini',
    systemPrompt: ''
  };

  /** 从 storage 加载 API 配置 */
  async function loadConfig() {
    try {
      var results = await Promise.all([
        RainCurtain.storage.get('api_key'),
        RainCurtain.storage.get('base_url'),
        RainCurtain.storage.get('model'),
        RainCurtain.storage.get('system_prompt')
      ]);
      config.apiKey = results[0] || '';
      config.baseUrl = results[1] || 'https://api.openai.com';
      config.model = results[2] || 'gpt-4o-mini';
      config.systemPrompt = results[3] || '';
    } catch (err) {
      console.error('Failed to load config:', err);
    }
  }

  /** 调用 LLM API 解析自然语言 */
  async function parseExpense(userInput) {
    if (!config.apiKey) {
      throw new Error('请先在设置中配置 API 密钥');
    }

    var base = config.baseUrl.replace(/\/+$/, '');
    var url = /\/v\d+$/.test(base)
      ? base + '/chat/completions'
      : base + '/v1/chat/completions';
    var body = {
      model: config.model,
      messages: [
        { role: 'system', content: config.systemPrompt },
        { role: 'user', content: userInput }
      ],
      temperature: 0
    };

    var response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + config.apiKey
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      var status = response.status;
      if (status === 401 || status === 403) {
        throw new Error('API 密钥无效或已过期，请检查设置');
      } else if (status === 429) {
        throw new Error('请求过于频繁，请稍后再试');
      } else if (status >= 500) {
        throw new Error('AI 服务暂时不可用，请稍后重试');
      }
      throw new Error('AI 服务请求失败（错误码 ' + status + '），请稍后重试');
    }

    var data;
    try {
      data = await response.json();
    } catch (_) {
      throw new Error('AI 服务返回了无法解析的响应，请稍后重试');
    }

    if (!data.choices || !data.choices[0] || !data.choices[0].message) {
      throw new Error('AI 服务返回了不完整的响应，请重试');
    }

    var content = data.choices[0].message.content.trim();
    return parseJsonResponse(content);
  }

  /** 从内容中提取 JSON 字符串（兼容 markdown 代码块、前后多余文字等） */
  function extractJson(content) {
    // 1. 尝试去掉 markdown 代码块包裹
    var cleaned = content.replace(/```json?\s*/g, '').replace(/```\s*/g, '').trim();

    // 2. 尝试直接解析
    try { return JSON.parse(cleaned); } catch (_) { /* 继续尝试 */ }

    // 3. 用正则提取第一个 { ... } 块
    var match = content.match(/\{[\s\S]*\}/);
    if (match) {
      try { return JSON.parse(match[0]); } catch (_) { /* 继续 */ }
    }

    return null;
  }

  /** 校验分类是否在预设列表中，不在则回退为"其他" */
  function validateCategory(category) {
    var validCategories = Object.keys(Utils.CATEGORY_ICONS);
    if (category && validCategories.indexOf(category) >= 0) {
      return category;
    }
    return '其他';
  }

  /** 解析 AI 返回的 JSON 内容 */
  function parseJsonResponse(content) {
    var parsed = extractJson(content);

    if (!parsed || typeof parsed !== 'object') {
      throw new Error('AI 返回了无法识别的内容，请换个描述方式重试');
    }

    if (!parsed.item && !parsed.amount) {
      throw new Error('AI 未能识别出消费项目和金额，请描述得更具体一些');
    }

    return {
      item: parsed.item || '未知',
      category: validateCategory(parsed.category),
      amount: Math.abs(Number(parsed.amount)) || 0,
      note: parsed.note || '',
      type: parsed.type === 'income' ? 'income' : 'expense'
    };
  }

  /** 从 storage 加载记录 */
  async function loadRecords() {
    var data = await RainCurtain.storage.get('records');
    return data || [];
  }

  /** 保存记录到 storage */
  async function saveRecords(records) {
    await RainCurtain.storage.set('records', records);
  }

  /** 加载钱包余额 */
  async function loadWalletBalance() {
    var balance = await RainCurtain.storage.get('wallet_balance');
    return (typeof balance === 'number') ? balance : 0;
  }

  /** 保存钱包余额 */
  async function saveWalletBalance(balance) {
    await RainCurtain.storage.set('wallet_balance', balance);
  }

  /** 写出 last_record 输出 */
  async function emitLastRecord(record) {
    if (!record) return;
    await RainCurtain.storage.set('last_record', JSON.stringify(record));
  }

  /** 调用 LLM API 解析语音录音（音频直接发送给大模型） */
  async function parseVoiceAudio(audioBase64, mimeType) {
    if (!config.apiKey) {
      throw new Error('请先在设置中配置 API 密钥');
    }

    var base = config.baseUrl.replace(/\/+$/, '');
    var url = /\/v\d+$/.test(base)
      ? base + '/chat/completions'
      : base + '/v1/chat/completions';

    var audioFormat = extractAudioFormat(mimeType);
    var baseMime = mimeType ? mimeType.split(';')[0].trim() : 'audio/webm';
    var dataUri = 'data:' + baseMime + ';base64,' + audioBase64;
    var audioSizeKB = Math.round((audioBase64.length * 3 / 4) / 1024);

    console.log('[Voice] 音频信息:', {
      mimeType: mimeType,
      format: audioFormat,
      base64Length: audioBase64.length,
      estimatedSizeKB: audioSizeKB,
      url: url,
      model: config.model
    });

    var body = {
      model: config.model,
      messages: [
        { role: 'system', content: config.systemPrompt },
        {
          role: 'user',
          content: [
            {
              type: 'input_audio',
              input_audio: {
                url: dataUri,
                format: audioFormat
              }
            },
            {
              type: 'text',
              text: '请识别音频中的内容并按要求返回JSON'
            }
          ]
        }
      ],
      temperature: 0
    };

    var bodyStr;
    try {
      bodyStr = JSON.stringify(body);
    } catch (e) {
      throw new Error('请求体序列化失败: ' + e.message);
    }

    var bodySizeMB = (bodyStr.length / (1024 * 1024)).toFixed(2);
    console.log('[Voice] 请求体大小:', bodySizeMB + ' MB');

    var response;
    try {
      console.log('[Voice] 开始发送音频请求...');
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + config.apiKey
        },
        body: bodyStr
      });
      console.log('[Voice] 音频请求成功返回, status:', response.status);
    } catch (networkErr) {
      console.error('[Voice] 网络请求异常:', networkErr);
      var detail = '网络请求失败';
      if (audioSizeKB > 1024) {
        detail += '（音频约 ' + audioSizeKB + ' KB，可能太大）';
      }
      detail += '\n请求地址: ' + url;
      detail += '\n模型: ' + config.model;
      detail += '\n音频格式: ' + mimeType + ' → ' + audioFormat;
      detail += '\n请求体大小: ' + bodySizeMB + ' MB';
      detail += '\n错误: ' + networkErr.message;
      throw new Error(detail);
    }

    if (!response.ok) {
      var errorBody = '';
      try { errorBody = await response.text(); } catch (_) {}
      console.error('[Voice] API 错误响应:', response.status, errorBody);

      var errMsg = 'API 请求失败 (HTTP ' + response.status + ')';
      if (response.status === 400) {
        errMsg += '\n该模型可能不支持音频输入';
        if (errorBody) errMsg += '\n' + errorBody.substring(0, 200);
      } else if (response.status === 401 || response.status === 403) {
        errMsg = 'API 密钥无效或已过期';
      } else if (response.status === 413) {
        errMsg = '音频文件太大 (' + audioSizeKB + ' KB)，请缩短录音时长';
      } else if (response.status === 429) {
        errMsg = '请求过于频繁，请稍后再试';
      } else if (response.status >= 500) {
        errMsg = 'AI 服务暂时不可用 (HTTP ' + response.status + ')';
      }
      if (errorBody && response.status !== 400) {
        errMsg += '\n' + errorBody.substring(0, 200);
      }
      throw new Error(errMsg);
    }

    var data;
    try {
      data = await response.json();
    } catch (_) {
      throw new Error('AI 服务返回了无法解析的响应');
    }

    if (!data.choices || !data.choices[0] || !data.choices[0].message) {
      console.error('[Voice] 异常响应体:', JSON.stringify(data).substring(0, 500));
      throw new Error('AI 服务返回了不完整的响应');
    }

    var content = data.choices[0].message.content;
    if (!content || !content.trim()) {
      throw new Error('AI 未返回有效内容，可能未识别到语音');
    }

    return parseJsonResponse(content.trim());
  }

  /** 从 MIME 类型中提取音频格式 */
  function extractAudioFormat(mimeType) {
    if (!mimeType) return 'mp3';
    var formatMap = {
      'audio/webm': 'webm',
      'audio/mp4': 'mp4',
      'audio/ogg': 'ogg',
      'audio/wav': 'wav',
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/flac': 'flac',
      'audio/aac': 'aac'
    };
    var baseMime = mimeType.split(';')[0].trim();
    return formatMap[baseMime] || 'mp3';
  }

  /** 检查 API 是否已配置 */
  function isConfigured() {
    return !!config.apiKey;
  }

  return {
    loadConfig: loadConfig,
    parseExpense: parseExpense,
    parseVoiceAudio: parseVoiceAudio,
    loadRecords: loadRecords,
    saveRecords: saveRecords,
    loadWalletBalance: loadWalletBalance,
    saveWalletBalance: saveWalletBalance,
    emitLastRecord: emitLastRecord,
    isConfigured: isConfigured
  };

})();
