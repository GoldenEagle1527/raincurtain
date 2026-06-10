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
- **资源加载：** 所有资源本地引用，禁止 CDN，但可以把CDN下载到本地lib引用
- **数据存储：** 使用 `RainCurtain.storage` API，禁止原生 `localStorage`

## 插件目录结构

```
my-plugin/
├── manifest.yml    # 必需：插件元数据与输入输出定义
├── index.html      # 必需：入口页面
├── lib/            # 可选：第三方库（从 CDN 下载到本地的 .js 文件）
├── styles/         # 可选：CSS 文件
└── scripts/        # 可选：JS 文件
```

- `lib/`：存放从 CDN 下载到本地的第三方库（如 `chart.umd.min.js`），在 HTML 中通过 `<script src="lib/xxx.js">` 引入，需在自编写的 JS 之前加载
- manifest.yml 的完整格式、字段定义和示例参见 `references/manifest.md`

## 开发工作流

### 1. 创建 manifest.yml

定义插件元数据、inputs 和 outputs。所有 input 必须提供 `default` 值。`object` 类型须定义 `schema`，`array` 类型须定义 `items`。格式详情参见 `references/manifest.md`。

### 2. 编写 HTML 入口

创建 `index.html`，使用语义化标签定义页面骨架。对于复杂插件，可以按分区组织（如页面骨架 → 弹窗层）。合理引入所需的 CSS 和 JS。_详见后续代码架构建议。_

### 3. 应用 UI 主题

使用系统注入的 MD3 CSS 变量实现深浅色自动切换。直接使用 Material Icons 字体类。主题变量和组件样式详情参见 `references/theme.md`。

### 4. 实现数据交互

- 输入输出：通过 `RainCurtain.getInput()` / `RainCurtain.setOutput()` 读写插件接口数据。详情参见 `references/api-core.md`。
- 持久化存储：通过 `RainCurtain.storage` API 执行结构化 CRUD 操作。详情参见 `references/storage.md`。
- 网络请求：通过标准 `fetch` 发起（系统自动绕过 CORS），支持 SSE 流式响应。详情参见 `references/network.md`。
- 文件系统 / 通知 / 剪贴板 / 屏幕方向等平台能力参见 `references/platform.md`。
- 联机通信（WebSocket / UDP）参见 `references/websocket.md` 和 `references/udp.md`。
- DNS 解析参见 `references/dns.md`。

### 5. 组织代码架构

根据插件规模决定代码拆分粒度。简单插件可以合并文件，复杂插件推荐按功能领域拆分以提升可维护性。_详见后续代码架构建议。_

## 关键 API 速查

`window.RainCurtain` 由宿主在页面加载前注入，所有插件环境下始终可用。

```javascript
// 输入输出
const value = await RainCurtain.getInput("input_name");
await RainCurtain.setOutput("output_name", value);

// 结构化存储（需在 manifest.yml 中声明 storage 表结构）
await RainCurtain.storage.insert("table", { col: val });
await RainCurtain.storage.query("table", { where, orderBy, limit, offset });
await RainCurtain.storage.update("table", values, where);
await RainCurtain.storage.delete("table", where);
await RainCurtain.storage.count("table", where);
await RainCurtain.storage.clear("table");

// 网络请求（系统自动绕过 CORS）
const resp = await fetch("https://api.example.com/data");
```

## 输入/输出处理

### 获取输入

```javascript
const videoFile = await RainCurtain.getInput("video_file");
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
await RainCurtain.setOutput("output_file", filePath);
```

- 在插件产出结果时调用，宿主自动处理持久化和传递
- name 对应 manifest.yml 中 outputs 声明的名称

## 代码架构建议

### 模块化方案

平台支持两种 JS 模块化方式：

**ES Modules（推荐）：** 使用 `<script type="module">` 加载入口，模块间通过标准 `import/export` 管理依赖。ES Modules 自带 defer 行为，无需额外处理初始化时序。

```html
<script type="module" src="scripts/main.js"></script>
```

```javascript
// scripts/main.js
import { VideoPlayer } from './video-player.js';
import { UIController } from './ui-controller.js';
// ...
```

**传统 script 标签：** 通过多个 `<script>` 标签顺序加载，模块通过 IIFE + 全局变量暴露接口。注意脚本加载顺序决定依赖关系——被依赖的模块必须先加载。需在 `DOMContentLoaded` 或 `document.readyState` 检查后初始化。

```html
<!-- 第三方库最先加载 -->
<script src="lib/chart.umd.min.js"></script>
<!-- 底层模块先于上层模块 -->
<script src="scripts/utils.js"></script>
<script src="scripts/api.js"></script>
<script src="scripts/ui.js"></script>
<!-- 入口文件最后加载 -->
<script src="scripts/app.js"></script>
```

### 灵活的目录结构与代码组织

- 根据插件复杂度合理组织代码。对于功能简单的极简插件，将所有逻辑写在少数几个文件甚至单文件（HTML+JS+CSS）中是完全可以接受的，避免过度设计。
- 对于复杂的插件，推荐按功能模块或组件将 JS 和 CSS 进行合理拆分，以保持代码可读性和可维护性。例如，将 API 请求、状态管理、UI 渲染分离。
- **CSS 组织建议：** 推荐使用清晰且模块化的 CSS 类名（如 BEM 命名风格）以避免样式冲突。优先使用系统注入的 MD3 主题变量（`--md-*`）来定义颜色、圆角、阴影等，确保系统主题适配。

### HTML/CSS/JS 实践指南

- **DOM 操作：** 推荐使用 `document.createElement` 来构建复杂的 DOM 结构，保持代码的结构化。如果使用 `innerHTML` 拼接动态内容，必须注意防范 XSS 注入风险。
- **语义化：** 尽可能使用语义化的 HTML 标签，如 `<header>`、`<main>`、`<button>` 等。
- **分离关注点：** 尽量保持 HTML（结构）、CSS（样式）和 JS（行为）的清晰分离，避免过度使用内联样式或内联事件。

_对于极其复杂的大型插件，如果需要更严谨的代码架构模板参考，可以查阅 `references/architecture.md`，但这并非强制要求。_

## 错误处理

对宿主 API 的调用应使用 try/catch 包裹，提供用户友好的降级 UI：

```javascript
try {
  const data = await RainCurtain.getInput("config");
  // 使用 data
} catch (e) {
  console.error('获取输入失败:', e);
  showFallbackUI(); // 提供手动输入入口或错误提示
}
```

网络请求同样需要异常处理，在 UI 上给予加载失败、空状态等友好提示。

## 文件下载最佳实践

在插件中下载视频、音频或其它大文件到本地时，为保证跨平台性能与稳定性，必须遵循以下规范：

- **优先使用动态 `<a>` 标签触发下载**：
  直接使用原生 JS 动态创建具有 `download` 属性的 `<a>` 标签并模拟点击，交由 RainCurtain 底层统一拦截并交给原生 Flutter 线程处理：
  ```javascript
  const a = document.createElement("a");
  a.href = fileUrl;
  a.download = suggestedFilename;
  a.style.display = "none";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  ```
  这样做可以利用 Flutter 原生端直接流式写入文件，规避 JS 侧大文件内存驻留和跨 bridge 传输大 Base64 数据带来的性能与兼容性风险，并且会自动触发平台统一的保存成功提示（SnackBar）。

- **避免手动拉起 `showSaveFilePicker` 进行手动写入**：
  严禁在插件 JS 代码中手动 `fetch` 大文件数据并使用 `showSaveFilePicker` 句柄进行前端分块 `write` 和 `close`。这种方案在大文件下极易引发桥接通道阻塞、内存溢出或静默失败。

- **宿主原生端 Stream 写入规范**：
  在宿主 Dart 代码（如处理底层拦截下载的 Handler）中，从网络响应 Stream 写入 `RandomAccessFile` 时，**严禁**使用并发的 `response.forEach` 异步回调。必须使用 `await for (final chunk in response)` 进行串行写入，防止由于并发异步写入同一文件句柄导致 `FileSystemException: An async operation is currently pending` 崩溃。

## 平台兼容性

- 使用标准 Web API 确保跨平台兼容
- 响应式设计适配桌面和移动端（推荐 CSS Grid `repeat(auto-fit, minmax(280px, 1fr))`）
- 同时支持触摸和鼠标操作
- 避免平台特定 API

## 开发检查清单

- [ ] 仅使用浏览器原生 API，未使用任何 Node.js 模块
- [ ] 仅使用本地资源（禁止 CDN），第三方库放置在 `lib/` 目录，未使用自定义字体
- [ ] 数据存储使用了 `RainCurtain.storage` API 而非原生 `localStorage`
- [ ] 成功接入了系统 MD3 CSS 主题变量
- [ ] `manifest.yml` 配置完整（包含输入输出及默认值，版本号格式正确）
- [ ] 确保在桌面和移动端（触摸与鼠标）均有良好的响应式适配
- [ ] 声明了 outputs 的插件，实际调用了 `RainCurtain.setOutput()` 写入输出值
- [ ] 宿主 API 调用和网络请求有适当的 try/catch 和降级处理
