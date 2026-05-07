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

创建 `index.html`，按依赖顺序加载 JS 文件（utils → state → api → ui → app），或使用 `<script type="module">`。

### 3. 应用 UI 主题

使用系统注入的 MD3 CSS 变量实现深浅色自动切换。直接使用 Material Icons 字体类。主题变量和组件样式详情参见 `references/theme.md`。

### 4. 实现数据交互

通过 `RainCurtain.storage` API 读写数据，通过标准 `fetch` 发起网络请求（系统自动绕过 CORS）。API 详情参见 `references/api.md`。

### 5. 组织代码架构

按职责拆分 JS 文件，遵循职责分离原则。架构模式和完整示例参见 `references/architecture.md`。

## 关键 API 速查

```javascript
// 数据存储
await RainCurtain.storage.get(key)       // 读取（自动回退到 manifest default）
await RainCurtain.storage.set(key, val)  // 保存
await RainCurtain.storage.remove(key)    // 删除

// 网络请求（系统自动绕过 CORS）
const resp = await fetch('https://api.example.com/data')

// 流式请求（SSE）— Accept 头包含 text/event-stream 时自动启用
const resp = await fetch(url, { headers: { 'Accept': 'text/event-stream' } })

// 宿主通信
new Notification("标题", { body: "内容" })
await navigator.clipboard.writeText("文本")
```

## 代码架构要求

### 文件拆分（必须）

禁止将所有逻辑写入单个 JS 文件。按职责边界拆分，每个文件只承担一个明确的职责领域。拆分粒度根据实际复杂度决定：

- **单个文件超过 200 行时**，审视其是否承担了多个职责，若是则继续拆分
- **同一职责领域内存在多个独立子模块时**（如多个不同的 API 端点、多个独立的 UI 面板），按子模块进一步拆分为独立文件
- **入口文件**始终独立，仅负责初始化、事件绑定和模块协调，不包含具体业务逻辑

拆分判断依据是职责边界而非固定模板。典型的职责领域包括但不限于：工具函数、状态管理、数据获取与持久化、DOM 渲染、业务流程协调。根据插件实际复杂度，这些领域可能合并（简单插件）或进一步细分（复杂插件）。

`references/architecture.md` 中提供了一个中等复杂度插件的拆分示例供参考，但不应机械套用。

### 核心规则

- 数据操作函数禁止直接操作 DOM
- UI 渲染函数禁止直接调用 API 或操作持久化存储
- 禁止使用 `innerHTML` 拼接动态内容，使用 `document.createElement` 构建 DOM
- 禁止将函数挂载到 `window` 对象，使用 `addEventListener` 绑定事件
- 每个函数只完成一个职责，函数体不超过 30 行
- 提取魔法数字和重复字符串为命名常量
- 状态变更通过专用函数，禁止直接赋值修改 state 属性

完整代码骨架、正反模式对比参见 `references/architecture.md`。

## 平台兼容性

- 使用标准 Web API 确保跨平台兼容
- 响应式设计适配桌面和移动端（推荐 CSS Grid `repeat(auto-fit, minmax(280px, 1fr))`）
- 同时支持触摸和鼠标操作
- 避免平台特定 API

## 开发检查清单

- [ ] 使用浏览器原生 API（非 Node.js 模块）
- [ ] 所有异步操作用 `try/catch` 包裹
- [ ] 使用 CSS 变量实现主题适配
- [ ] 使用系统全局字体（非必要禁止自定义字体）
- [ ] 所有资源本地引用（禁止 CDN）
- [ ] manifest.yml 版本号符合 X.Y.Z 格式
- [ ] manifest.yml 定义了 inputs 和 outputs（即使为空列表 `[]`）
- [ ] 所有 input 都有 default 值
- [ ] object 类型已定义 schema，array 类型已定义 items
- [ ] 响应式布局适配桌面和移动端
- [ ] 同时支持触摸和鼠标操作
- [ ] 使用 RainCurtain.storage API 而非原生 localStorage
- [ ] JS 代码按职责边界拆分，单文件不超过 200 行
- [ ] 数据操作函数不直接操作 DOM
- [ ] 使用 createElement 构建 DOM，使用 addEventListener 绑定事件
- [ ] 每个函数职责单一，函数体不超过 30 行
- [ ] 无魔法数字和重复字符串，常量已提取命名
