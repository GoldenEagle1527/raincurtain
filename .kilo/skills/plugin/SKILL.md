---
name: plugin
description: "HTML/CSS/JS plugins for Flutter InAppWebView with unrestricted browser APIs. This skill should be used when creating plugins, writing manifest.yml, implementing plugin UI, or organizing plugin code architecture for the Rain Curtain platform."
---

# Rain Curtain 插件开发

本技能提供 Rain Curtain 平台 HTML/CSS/JS 插件的开发指导，涵盖插件结构、API 约束、UI 主题和代码架构规范。

## 核心约束

- **运行环境：** Flutter InAppWebView（完全解除浏览器安全限制）
- **支持平台：** 仅 Windows 和 Android，插件必须在两个平台上均可运行
- **API 原则：** 必须使用浏览器原生 API，严禁使用 Node.js 模块（`require('fs')` / `import fs`）
- **字体：** 系统已注入 NotoSerifSC（思源宋体），非必要禁止自定义字体
- **资源加载：** 所有资源本地引用，禁止 CDN
- **数据存储：** 使用 `RainCurtain.storage` API，禁止原生 `localStorage`

## 插件目录结构

```
my-plugin/
├── manifest.yml    # 必需：插件元数据与输入输出定义
├── index.html      # 必需：入口页面
├── styles/         # 可选：CSS 文件
└── scripts/        # 可选：JS 文件
```

manifest.yml 的完整格式、字段定义和示例参见 `references/manifest.md`。

## 开发工作流

### 1. 创建 manifest.yml

定义插件元数据、inputs 和 outputs。所有 input 必须提供 `default` 值。`object` 类型须定义 `schema`，`array` 类型须定义 `items`。格式详情参见 `references/manifest.md`。

### 2. 编写 HTML 入口

创建 `index.html`，使用语义化标签定义页面骨架。对于复杂插件，可以按分区组织（如页面骨架 → 弹窗层）。合理引入所需的 CSS 和 JS。*详见后续代码架构建议。*

### 3. 应用 UI 主题

使用系统注入的 MD3 CSS 变量实现深浅色自动切换。直接使用 Material Icons 字体类。主题变量和组件样式详情参见 `references/theme.md`。

### 4. 实现数据交互

通过 `RainCurtain.storage` API 读写数据，通过标准 `fetch` 发起网络请求（系统自动绕过 CORS）。API 详情参见 `references/api.md`。

### 5. 组织代码架构

根据插件规模决定代码拆分粒度。简单插件可以合并文件，复杂插件推荐按功能领域拆分以提升可维护性。*详见后续代码架构建议。*

## 关键 API 速查

```javascript
// 获取输入值
const value = await RainCurtain.getInput('input_name')

// 设置输出值
await RainCurtain.setOutput('output_name', value)

// 结构化存储（需在 manifest.yml 中声明 storage 表结构）
await RainCurtain.storage.insert('table', { col: val })       // 插入
await RainCurtain.storage.query('table', { where, orderBy, limit, offset })  // 查询
await RainCurtain.storage.update('table', values, where)      // 更新
await RainCurtain.storage.delete('table', where)              // 删除
await RainCurtain.storage.count('table', where)               // 计数
await RainCurtain.storage.clear('table')                      // 清空表

// 网络请求（系统自动绕过 CORS）
const resp = await fetch('https://api.example.com/data')

// 流式请求（SSE）— Accept 头包含 text/event-stream 时自动启用
const resp = await fetch(url, { headers: { 'Accept': 'text/event-stream' } })

// 宿主通信
new Notification("标题", { body: "内容" })
await navigator.clipboard.writeText("文本")

// 文件系统访问（已透明代理，两个平台行为一致）
// 保存文件
const handle = await window.showSaveFilePicker({ suggestedName: 'data.json' })
const writable = await handle.createWritable()
await writable.write(JSON.stringify(data))
await writable.close()

// 打开文件
const [fileHandle] = await window.showOpenFilePicker()
const file = await fileHandle.getFile()
const text = await file.text()

// 选择目录并遍历
const dirHandle = await window.showDirectoryPicker()
for await (const [name, entry] of dirHandle.entries()) { /* ... */ }
```

## 输入/输出处理

`window.RainCurtain` 由宿主在页面加载前注入，所有插件环境下始终可用。

### 获取输入

```javascript
const videoFile = await RainCurtain.getInput('video_file');
if (videoFile) {
  await loadVideo(videoFile);
} else {
  showFilePicker(); // 无输入时提供手动入口
}
```

- `getInput(name)` 返回 manifest inputs 中对应名称的当前值
- 值可能来自外部动态提供，也可能是 manifest 中的 default
- 返回 null 或空值时，插件应提供用户手动输入的 UI 入口

### 设置输出

```javascript
await RainCurtain.setOutput('output_file', filePath);
```

- 在插件产出结果时调用，宿主自动处理持久化和传递
- name 对应 manifest.yml 中 outputs 声明的名称

## 代码架构建议

### 灵活的目录结构与代码组织

*   根据插件复杂度合理组织代码。对于功能简单的极简插件，将所有逻辑写在少数几个文件甚至单文件（HTML+JS+CSS）中是完全可以接受的，避免过度设计。
*   对于复杂的插件，推荐按功能模块或组件将 JS 和 CSS 进行合理拆分，以保持代码可读性和可维护性。例如，将 API 请求、状态管理、UI 渲染分离。
*   **CSS 组织建议：** 推荐使用清晰且模块化的 CSS 类名（如 BEM 命名风格）以避免样式冲突。优先使用系统注入的 MD3 主题变量（`--md-*`）来定义颜色、圆角、阴影等，确保系统主题适配。

### HTML/CSS/JS 实践指南

*   **DOM 操作：** 推荐使用 `document.createElement` 来构建复杂的 DOM 结构，保持代码的结构化。如果使用 `innerHTML` 拼接动态内容，必须注意防范 XSS 注入风险。
*   **全局污染：** 尽量避免将函数挂载到 `window` 对象，推荐使用模块化导出或在作用域内绑定事件。但在特定的宿主环境交互中，如确有必要也可使用。
*   **语义化：** 尽可能使用语义化的 HTML 标签，如 `<header>`、`<main>`、`<button>` 等。
*   **分离关注点：** 尽量保持 HTML（结构）、CSS（样式）和 JS（行为）的清晰分离，避免过度使用内联样式或内联事件。

*对于极其复杂的大型插件，如果需要更严谨的代码架构模板参考，可以查阅 `references/architecture.md`，但这并非强制要求。*

## 平台兼容性

- 使用标准 Web API 确保跨平台兼容
- 响应式设计适配桌面和移动端（推荐 CSS Grid `repeat(auto-fit, minmax(280px, 1fr))`）
- 同时支持触摸和鼠标操作
- 避免平台特定 API

## 开发检查清单

- [ ] 仅使用浏览器原生 API，未使用任何 Node.js 模块。
- [ ] 仅使用本地资源（禁止 CDN），未使用自定义字体。
- [ ] 数据存储使用了 `RainCurtain.storage` API 而非原生 `localStorage`。
- [ ] 成功接入了系统 MD3 CSS 主题变量。
- [ ] `manifest.yml` 配置完整（包含输入输出及默认值，版本号格式正确）。
- [ ] 确保在桌面和移动端（触摸与鼠标）均有良好的响应式适配。
- [ ] 声明了 outputs 的插件，实际调用了 `RainCurtain.setOutput()` 写入输出值。
