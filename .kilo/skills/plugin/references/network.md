# 网络请求参考

插件运行在 `http://localhost:<动态端口>`（端口由系统自动分配）。所有跨域请求（`fetch` / `XMLHttpRequest`）由系统自动拦截，通过 Flutter 的 `http` 包发起，彻底绕过 CORS 限制。无需修改代码，直接使用标准浏览器 API。

## 基础用法

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

## 请求取消（AbortController）

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

## 流式响应（SSE / AI 逐字输出）

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

## FormData 文件上传

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

## GET 请求缓存

GET 请求结果按 `Cache-Control: max-age` 自动缓存（默认 60 秒，最多缓存 50 条），重复请求直接命中缓存：

```javascript
// 第一次：发起网络请求
const r1 = await fetch('https://api.example.com/config');
// 第二次（60 秒内）：命中缓存，零延迟返回
const r2 = await fetch('https://api.example.com/config');
```

## 所有跨域请求自动具备

- CORS 绕过（fetch 和 XMLHttpRequest 均自动拦截）
- AbortController 取消
- 性能日志（Flutter 控制台）
- GET 缓存
