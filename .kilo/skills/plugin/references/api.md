# API 参考

## RainCurtain 存储 API

所有插件通过 `window.RainCurtain` API 进行数据操作。插件的存储表结构需在 `manifest.yml` 的 `storage` 字段中声明。

### 元数据

```javascript
RainCurtain.pluginId    // string - 插件 ID
```

### 结构化存储 API

插件通过 `RainCurtain.storage` 对 manifest 中声明的表执行 CRUD 操作。每个表自动包含 `_id` 自增主键。

```javascript
// 插入（单行或多行）
await RainCurtain.storage.insert(table, rows)
// rows: { col: val } 或 [{ col: val }, ...]
// 返回: { insertedCount: N }

// 查询
await RainCurtain.storage.query(table, options)
// options: { where: { col: val }, orderBy: 'col DESC', limit: 10, offset: 0 }
// 返回: [{ _id: 1, col: val, ... }, ...]

// 更新
await RainCurtain.storage.update(table, values, where)
// values: { col: newVal }
// where: { _id: 1 }  可选，为空则更新全部
// 返回: { updatedCount: N }

// 删除
await RainCurtain.storage.delete(table, where)
// where: { _id: 1 }  可选，为空则删除全部
// 返回: { deletedCount: N }

// 计数
await RainCurtain.storage.count(table, where)
// 返回: N

// 清空表
await RainCurtain.storage.clear(table)
```

### manifest.yml 中的表声明

```yaml
storage:
  - name: "records"         # 表名（插件内唯一）
    columns:
      - name: "item"
        type: "text"        # 支持: text, integer, real, boolean
      - name: "amount"
        type: "real"
      - name: "created_at"
        type: "text"
```

支持的列类型：

| 类型 | SQLite | JS 值 | 说明 |
|------|--------|-------|------|
| `text` | TEXT | string | 字符串 |
| `integer` | INTEGER | number | 整数 |
| `real` | REAL | number | 浮点数 |
| `boolean` | INTEGER (0/1) | boolean | 布尔值，JS 侧自动转换 |

### 溯流模式下的变量池拦截

- **insert / update 时**：如果写入的列名匹配 `outputMappings` 中的 key，对应值会同步写入变量池
- **query 时**：如果 where 条件的列名匹配 `inputMappings` 中的 key，会优先从变量池获取值

### 存储使用示例

```javascript
// 插入一条记录
const result = await RainCurtain.storage.insert('records', {
  item: '午饭',
  amount: 18.5,
  created_at: new Date().toISOString()
});
// result: { insertedCount: 1 }

// 批量插入
await RainCurtain.storage.insert('records', [
  { item: '午饭', amount: 18 },
  { item: '晚饭', amount: 25 }
]);

// 查询（带条件和排序）
const rows = await RainCurtain.storage.query('records', {
  where: { type: 'expense' },
  orderBy: 'created_at DESC',
  limit: 20
});

// 按 _id 更新
await RainCurtain.storage.update('records', { amount: 20 }, { _id: 1 });

// 按条件删除
await RainCurtain.storage.delete('records', { _id: 1 });

// 计数
const total = await RainCurtain.storage.count('records');
const expenses = await RainCurtain.storage.count('records', { type: 'expense' });

// 清空表
await RainCurtain.storage.clear('records');
```

### 初始化模式

```javascript
async function init() {
  // 查询已有数据
  const records = await RainCurtain.storage.query('records', {
    orderBy: 'created_at DESC',
    limit: 50
  });
  
  if (records.length > 0) {
    renderRecords(records);
  }
  
  // 统计
  const count = await RainCurtain.storage.count('records');
  updateStats(count);
}
```

**存储特点：**

- 每个插件独立的结构化表，按列存储
- 支持 text / integer / real / boolean 四种列类型
- boolean 列在 JS 层自动转换（true/false ↔ 0/1）
- 每个表自动包含 `_id` 自增主键
- 表结构由 manifest.yml 声明，安装时自动建表
- 卸载插件时自动清理所有表

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
