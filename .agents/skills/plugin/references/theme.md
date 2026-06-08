# UI 主题系统参考

## MD3 CSS 变量

系统自动注入 MD3 CSS 变量，支持深浅色自动切换。

### 主要颜色

```css
--md-primary                /* 主色调背景 */
--md-on-primary             /* 主色调文字 */
--md-primary-container      /* 主色调容器背景 */
--md-on-primary-container   /* 主色调容器文字 */
```

### 表面颜色

```css
--md-surface                /* 基础背景 */
--md-on-surface             /* 基础文字 */
--md-surface-container      /* 卡片背景 */
--md-surface-container-high /* 高层级背景 */
```

### 其他变量

```css
--md-outline-variant        /* 边框/分割线 */
--md-error                  /* 错误状态颜色 */
--md-success                /* 成功状态颜色 */
--md-radius-button (20px)   /* 按钮圆角 */
--md-radius-card (12px)     /* 卡片圆角 */
--md-elevation-1            /* 卡片阴影 */
--md-font                   /* 全局字体 (NotoSerifSC 思源宋体) */
```

## 核心组件样式

### Filled Button

```css
.btn-primary {
  background: var(--md-primary);
  color: var(--md-on-primary);
  border-radius: 20px;
  padding: 10px 24px;
}
```

### Card

```css
.card {
  background: var(--md-surface-container);
  border-radius: 12px;
  box-shadow: var(--md-elevation-1);
}
```

## 字体使用原则

- 系统已注入 NotoSerifSC（思源宋体）作为全局字体
- 直接使用 `font-family: var(--md-font)` 或继承默认字体
- 非必要禁止使用自定义字体，避免字体冲突和加载开销
- 如需等宽代码字体，使用系统字体栈：`'Consolas', 'Monaco', monospace`

## Material Icons

系统已注入 Material Icons 字体，直接使用：

```html
<span class="material-icons">home</span>
<span class="material-icons-outlined">favorite</span>
<span class="material-icons-rounded">account_circle</span>
```

### 样式变体

| 类名 | 样式 |
|------|------|
| `material-icons` | 默认填充样式 |
| `material-icons-outlined` | 轮廓样式 |
| `material-icons-rounded` | 圆角样式 |
| `material-icons-sharp` | 锐角样式 |
| `material-icons-two-tone` | 双色样式 |

## 响应式布局

推荐使用 CSS Grid 实现响应式布局：

```css
.grid-container {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 16px;
}
```
