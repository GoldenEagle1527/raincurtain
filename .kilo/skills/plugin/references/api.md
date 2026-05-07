# API 参考

## RainCurtain 存储 API

所有插件通过 `window.RainCurtain` API 进行数据操作。

### 元数据

```javascript
RainCurtain.pluginId    // string - 插件 ID
```

### 通用存储 API

```javascript
await RainCurtain.storage.get(key)      // 读取数据（自动回退到 manifest 默认值）
await RainCurtain.storage.set(key, val) // 保存数据
await RainCurtain.storage.remove(key)   // 删除数据
await RainCurtain.storage.clear()       // 清空所有数据
await RainCurtain.storage.keys()        // 获取所有键
```

### `storage.get(key)` 值获取优先级

1. 溯流模式：变量池映射值 → 本地存储值 → manifest `default` 值 → `null`
2. 雨幕模式：本地存储值 → manifest `default` 值 → `null`

当 key 对应 manifest 中的某个 input 且设有 `default` 值时，本地存储为空也不会返回 `null`，而是返回默认值。

### 存储使用示例

```javascript
// 保存任意 JSON 可序列化的值
await RainCurtain.storage.set('preferences', {
  theme: 'dark',
  language: 'zh-CN',
});

// 读取数据
const prefs = await RainCurtain.storage.get('preferences');
// 返回: { theme: 'dark', language: 'zh-CN' } 或 null

// 删除数据
await RainCurtain.storage.remove('preferences');

// 清空所有数据
await RainCurtain.storage.clear();

// 获取所有键
const keys = await RainCurtain.storage.keys();
```

**存储特点：**

- 自动持久化到宿主文件系统
- 支持对象、数组、字符串、数字、布尔值
- 按插件隔离存储
- 宿主可配置数据流映射，插件无需感知

### 初始化模式

```javascript
async function init() {
  // 读取数据
  const userId = await RainCurtain.storage.get('user_id');
  if (userId) {
    processData(userId);
  }

  // 恢复持久化状态
  const savedState = await RainCurtain.storage.get('app_state');
  if (savedState) {
    restoreState(savedState);
  }

  // 保存数据
  await RainCurtain.storage.set('app_state', currentState);

  // 保存结果（若 key 匹配 manifest outputs 且有 outputMappings，自动同步到变量池）
  await RainCurtain.storage.set('result', processedData);
}
```

---

## 网络请求

插件运行在 `http://localhost:<动态端口>`（端口由系统自动分配）。所有跨域请求（`fetch` / `XMLHttpRequest`）由系统自动拦截，通过 Flutter 的 `http` 包发起，彻底绕过 CORS 限制。无需修改代码，直接使用标准浏览器 API。

### 基础用法

```javascript
const response = await fetch('https://api.example.com/v1/data', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_TOKEN',
  },
  body: JSON.stringify({ query: 'hello' }),
});
const data = await response.json();
```

### 请求取消（AbortController）

```javascript
const controller = new AbortController();
fetch('https://api.example.com/slow', { signal: controller.signal })
  .then((r) => r.json())
  .catch((e) => {
    if (e.name === 'AbortError') console.log('已取消');
  });

// 取消请求
controller.abort();
```

### 流式响应（SSE / AI 逐字输出）

当 `Accept` 请求头包含 `text/event-stream` 时，系统自动切换为流式传输，`response.body` 是真正的 `ReadableStream`：

```javascript
const response = await fetch('https://api.openai.com/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer YOUR_KEY',
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream'   // 触发流式模式
  },
  body: JSON.stringify({ model: 'gpt-4o', messages: [...], stream: true })
});

const reader = response.body.getReader();
const decoder = new TextDecoder();
while (true) {
  const { done, value } = await reader.read();
  if (done) break;
  const text = decoder.decode(value, { stream: true });
  for (const line of text.split('\n')) {
    if (line.startsWith('data: ') && line !== 'data: [DONE]') {
      const json = JSON.parse(line.slice(6));
      process(json.choices[0].delta.content);
    }
  }
}
```

### FormData 文件上传

系统支持 `FormData` 中包含 `File` 或 `Blob` 对象，自动通过 `multipart/form-data` 发送：

```javascript
const formData = new FormData();
formData.append('name', 'Alice');
formData.append('avatar', fileInput.files[0]);  // File 对象

const response = await fetch('https://api.example.com/upload', {
  method: 'POST',
  body: formData,   // 自动处理 multipart 编码
});
```

### GET 请求缓存

GET 请求结果按 `Cache-Control: max-age` 自动缓存（默认 60 秒，最多缓存 50 条），重复请求直接命中缓存：

```javascript
// 第一次：发起网络请求
const r1 = await fetch('https://api.example.com/config');
// 第二次（60 秒内）：命中缓存，零延迟返回
const r2 = await fetch('https://api.example.com/config');
```

### 所有跨域请求自动具备

- CORS 绕过（fetch 和 XMLHttpRequest 均自动拦截）
- AbortController 取消
- 性能日志（Flutter 控制台）
- GET 缓存

---

## 宿主通信

插件已内置以下 polyfill，直接使用浏览器 API：

```javascript
// 通知 API（已 polyfill）
new Notification("标题", { body: "内容" });

// 剪贴板 API（已 polyfill）
await navigator.clipboard.writeText("文本");
const text = await navigator.clipboard.readText();

// 自定义宿主通信（高级用法）
window.flutter_inappwebview.callHandler("handlerName", data);
```

---

## 已放行的浏览器权限

以下高级权限无需用户授权即可直接调用：

- 摄像头 (`navigator.mediaDevices.getUserMedia()`)
- 麦克风
- 地理位置 (`navigator.geolocation.getCurrentPosition()`)
- 剪贴板 (`navigator.clipboard`)
- 通知 (`new Notification()`)
- 文件系统访问 (`window.showOpenFilePicker()` / `window.showSaveFilePicker()`)
- USB、串口、MIDI、传感器、字体枚举
