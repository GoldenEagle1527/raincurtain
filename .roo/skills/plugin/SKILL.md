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
```

**icon 字段：**

- Material Icons: `material:home` / `material:favorite:outlined`
- 图片文件: `./icon.png` / `./assets/logo.svg`

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

## 数据持久化

系统自动管理插件数据,无需手动操作：

**LocalStorage：** 自动同步到宿主文件系统,跨会话持久化
**Cookie：** 自动保存和恢复,支持完整的 Cookie 属性

```javascript
// LocalStorage 正常使用,自动持久化
localStorage.setItem("key", "value");
const value = localStorage.getItem("key");

// Cookie 通过 document.cookie 或服务器 Set-Cookie 设置
document.cookie = "name=value; path=/";
```

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
