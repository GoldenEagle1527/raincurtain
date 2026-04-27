---
name: plugin
description: HTML/CSS/JS plugins for Flutter InAppWebView with unrestricted browser APIs (camera/mic/clipboard/notifications/file access). Use browser native APIs only (navigator.mediaDevices/Notification/clipboard), not Node.js modules. MD3 blue theme with auto dark mode. Use when creating plugins, writing manifest.yml, or implementing plugin UI.
---

# Rain Curtain 插件开发

## 核心约束

**运行环境：** Flutter InAppWebView (完全解除浏览器安全限制)
**支持平台：** 仅支持 Windows 和 Android,插件必须在两个平台上均可运行
**API 使用原则：** 必须使用浏览器原生 API,严禁使用 Node.js 模块

- ✅ 使用 `navigator.mediaDevices.getUserMedia()` 访问摄像头/麦克风
- ✅ 使用 `new Notification()` 发送通知
- ✅ 使用 `navigator.clipboard.writeText()` 操作剪贴板
- ✅ 使用 `navigator.geolocation.getCurrentPosition()` 获取位置
- ✅ 使用 `window.showOpenFilePicker()` / `window.showSaveFilePicker()` 访问文件系统
- ❌ 禁止 `require('fs')` / `import fs from 'fs'`
- ❌ 禁止 `require('path')` / Node.js 原生模块

**已放行的高级权限：** 摄像头、麦克风、地理位置、剪贴板、通知、文件系统访问、USB、串口、MIDI、传感器、字体枚举等,无需用户授权即可直接调用。

## 插件结构

```
my-plugin/
├── manifest.yml    # 必需：插件元数据
├── index.html      # 必需：入口页面
├── styles/         # 可选：CSS 文件
└── scripts/        # 可选：JS 文件
```

**manifest.yml 格式：**

```yaml
name: "插件名称"
description: "插件描述"
version: "1.0.0" # 语义化版本 X.Y.Z
author: "作者名"
icon: "material:extension" # Material Icons 或图片路径

# 可选：输入输出定义（用于溯流模式）
inputs:
  - name: "input1"           # 输入变量名称
    type: "string"           # 数据类型：string, number, boolean, object, array
    description: "输入描述"   # 变量说明
    required: true           # 是否必需（默认false）
  - name: "input2"
    type: "number"
    description: "数值输入"
    required: false

outputs:
  - name: "output1"          # 输出变量名称
    type: "object"           # 数据类型
    description: "输出描述"   # 变量说明
  - name: "output2"
    type: "string"
    description: "文本输出"
```

**icon 字段：**

- Material Icons: `material:home` / `material:favorite:outlined`
- 图片文件: `./icon.png` / `./assets/logo.svg`

**输入输出定义说明：**

- **inputs/outputs**：可选字段，定义后可在溯流模式中使用
- **name**：变量名称，必须唯一，仅支持字母、数字、下划线
- **type**：数据类型，支持 `string`, `number`, `boolean`, `object`, `array`
- **description**：变量说明，用于UI显示
- **required**：是否必需（仅对inputs有效），默认为false

## 运行模式

Rain Curtain 支持两种运行模式：

### 1. 雨幕模式（独立模式）

- 插件独立运行，不依赖其他插件
- 使用 `localStorage` 保存状态
- 适合独立工具类插件

### 2. 溯流模式（协作模式）

- 插件在"池"中运行，可与其他插件协作
- 通过变量池共享数据
- 支持输入输出映射，实现数据流转
- 适合需要数据处理流水线的场景

## 溯流模式 API

当插件在溯流模式的池中运行时，可使用以下API与变量池交互：

### 获取输入变量

```javascript
// 获取单个输入变量
const value = await window.raincurtain.getInput('input1');

// 获取所有输入变量
const inputs = await window.raincurtain.getAllInputs();
// 返回: { input1: "value1", input2: 123 }
```

### 设置输出变量

```javascript
// 设置单个输出变量
await window.raincurtain.setOutput('output1', { result: 'success' });

// 设置多个输出变量
await window.raincurtain.setOutputs({
  output1: { result: 'success' },
  output2: 'completed'
});
```

### 监听输入变化

```javascript
// 监听特定输入变量的变化
window.raincurtain.onInputChange('input1', (newValue) => {
  console.log('input1 changed:', newValue);
  // 处理新值
});

// 监听所有输入变量的变化
window.raincurtain.onInputChange('*', (changes) => {
  console.log('inputs changed:', changes);
  // changes: { input1: newValue1, input2: newValue2 }
});
```

### 检测运行模式

```javascript
// 检测当前是否在溯流模式中运行
if (window.raincurtain && window.raincurtain.isStreamMode) {
  console.log('Running in stream mode');
  // 使用输入输出API
} else {
  console.log('Running in rain mode');
  // 独立运行逻辑
}
```

### 完整示例

```javascript
// 数据处理插件示例
(async function() {
  // 检测运行模式
  if (!window.raincurtain?.isStreamMode) {
    console.log('This plugin requires stream mode');
    return;
  }

  // 获取输入
  const inputText = await window.raincurtain.getInput('text');
  const options = await window.raincurtain.getInput('options');

  // 处理数据
  const result = processData(inputText, options);

  // 输出结果
  await window.raincurtain.setOutput('result', result);
  await window.raincurtain.setOutput('status', 'completed');

  // 监听输入变化，实时处理
  window.raincurtain.onInputChange('text', async (newText) => {
    const newResult = processData(newText, options);
    await window.raincurtain.setOutput('result', newResult);
  });
})();

function processData(text, options) {
  // 数据处理逻辑
  return { processed: text.toUpperCase() };
}
```

## UI 主题系统

系统自动注入 MD3 CSS 变量,支持深浅色自动切换：

```css
/* 主要颜色 */
--md-primary                /* 主色调背景 */
--md-on-primary             /* 主色调文字 */
--md-primary-container      /* 主色调容器背景 */
--md-on-primary-container   /* 主色调容器文字 */

/* 表面颜色 */
--md-surface                /* 基础背景 */
--md-on-surface             /* 基础文字 */
--md-surface-container      /* 卡片背景 */
--md-surface-container-high /* 高层级背景 */

/* 其他 */
--md-outline-variant        /* 边框/分割线 */
--md-error / --md-success   /* 状态颜色 */
--md-radius-button (20px)   /* 按钮圆角 */
--md-radius-card (12px)     /* 卡片圆角 */
--md-elevation-1            /* 卡片阴影 */
--md-font                   /* 全局字体 (NotoSerifSC 思源宋体) */
```

**字体使用原则：**

- ✅ 系统已注入 NotoSerifSC (思源宋体) 作为全局字体
- ✅ 直接使用 `font-family: var(--md-font)` 或继承默认字体
- ❌ **非必要禁止使用自定义字体**,避免字体冲突和加载开销
- ⚠️ 如需特殊字体 (如等宽代码字体),使用系统字体栈: `'Consolas', 'Monaco', monospace`

**核心组件样式：**

```css
/* Filled Button */
background: var(--md-primary);
color: var(--md-on-primary);
border-radius: 20px;
padding: 10px 24px;

/* Card */
background: var(--md-surface-container);
border-radius: 12px;
box-shadow: var(--md-elevation-1);
```

## Material Icons

系统已注入字体,直接使用：

```html
<span class="material-icons">home</span>
<span class="material-icons-outlined">favorite</span>
<span class="material-icons-rounded">account_circle</span>
```

## Material Icons 样式变体

支持 5 种样式变体：

- `material-icons` - 默认填充样式
- `material-icons-outlined` - 轮廓样式
- `material-icons-rounded` - 圆角样式
- `material-icons-sharp` - 锐角样式
- `material-icons-two-tone` - 双色样式

## 网络请求与 CORS

插件运行在 `http://localhost:8080`。所有**跨域请求**（`fetch` / `XMLHttpRequest`）由系统自动拦截，通过 Flutter 的 `http` 包发起，彻底绕过浏览器 CORS 限制。无需修改代码，直接使用标准浏览器 API 即可。

### 基础用法（推荐）

```javascript
// 直接使用标准 fetch，系统自动绕过 CORS
const response = await fetch('https://api.example.com/v1/data', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer YOUR_TOKEN'
  },
  body: JSON.stringify({ query: 'hello' })
});
const data = await response.json();
```

### 请求取消（AbortController）

```javascript
const controller = new AbortController();
fetch('https://api.example.com/slow', { signal: controller.signal })
  .then(r => r.json())
  .catch(e => { if (e.name === 'AbortError') console.log('已取消'); });

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
  // 逐块处理 SSE 数据
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
  body: formData   // 自动处理 multipart 编码
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

### 旧方式：手动代理（仍可用）

如遇到 CORS 头错误等特殊情况，仍可手动使用 `/__proxy__/`：

```javascript
const proxyUrl = `/__proxy__/${encodeURIComponent('https://api.example.com/v1/endpoint')}`;
const response = await fetch(proxyUrl, { method: 'POST', ... });
```

`/__proxy__/` 现在也支持流式响应（SSE），无需额外配置。

**所有请求自动具备：**
- CORS 绕过
- AbortController 取消
- 性能日志（Flutter 控制台）
- GET 缓存

## 数据持久化

系统自动管理插件数据：

**LocalStorage：** 自动同步到宿主文件系统,跨会话持久化

```javascript
// LocalStorage 正常使用,自动持久化
localStorage.setItem("key", "value");
const value = localStorage.getItem("key");
```

**注意：** Cookie 存储已被移除，请使用 LocalStorage 代替。

## 宿主通信

插件已内置以下 polyfill,直接使用浏览器 API 即可：

```javascript
// 通知 API (已 polyfill)
new Notification("标题", { body: "内容" });

// 剪贴板 API (已 polyfill)
await navigator.clipboard.writeText("文本");
const text = await navigator.clipboard.readText();

// 自定义宿主通信 (高级用法)
window.flutter_inappwebview.callHandler("handlerName", data);
```

## 响应式布局

使用 CSS Grid 实现响应式：

```css
.grid-container {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}
```

## 平台兼容性

插件必须同时支持 Windows 和 Android 平台：

- 避免使用平台特定的 API 或特性
- 使用标准 Web API 确保跨平台兼容
- 响应式设计适配不同屏幕尺寸 (桌面/移动端)
- 触摸和鼠标交互均需支持

## 开发检查清单

- [ ] 使用浏览器原生 API (非 Node.js 模块)
- [ ] 所有异步操作用 `try/catch` 包裹
- [ ] 使用 CSS 变量实现主题适配
- [ ] 使用系统全局字体 (非必要禁止自定义字体)
- [ ] 所有资源本地引用 (禁止 CDN)
- [ ] manifest.yml 版本号符合 X.Y.Z 格式
- [ ] 响应式布局适配桌面和移动端
- [ ] 同时支持触摸和鼠标操作
- [ ] 在 Windows 和 Android 上测试通过
- [ ] 如需溯流模式，正确定义 inputs/outputs
- [ ] 使用 LocalStorage 而非 Cookie 存储数据
