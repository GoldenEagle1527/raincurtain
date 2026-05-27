# API 参考

## RainCurtain API

所有插件通过 `window.RainCurtain` API 进行数据操作和输入获取。

### 元数据

```javascript
RainCurtain.pluginId    // string - 插件 ID
```

### 输入获取

```javascript
const value = await RainCurtain.getInput(name)
// name: manifest.yml 中 inputs 定义的名称
// 返回: 输入值（可能来自外部动态提供，也可能是 manifest default）
//       未找到时返回 null
```

输入值的来源由宿主自动管理，插件不需要关心。

### 输出设置

```javascript
await RainCurtain.setOutput(name, value)
// name: manifest.yml 中 outputs 定义的名称
// value: 要输出的值
// 宿主自动持久化并可能将此值传递给其他组件
```

声明了 outputs 的插件，应在产出结果时调用此 API。

### 结构化存储 API

插件的存储表结构需在 `manifest.yml` 的 `storage` 字段中声明。

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

### 表结构变更行为

插件更新版本时，如果 `storage` 中的表结构发生变化，系统会尝试兼容迁移以保留用户数据：

| 变更类型 | 处理方式 | 用户数据 |
|---|---|---|
| **新增列** | 自动 `ALTER TABLE ADD COLUMN` | 已有数据保留，新列值为 `null` |
| **删除列** | 不做处理，旧列保留在表中 | 已有数据保留，旧列对 API 不可见 |
| **修改列类型** | 删除并重建整个表 | **数据丢失** |

简单来说：只要不改变已有列的类型，用户数据就不会丢失。如果需要变更列类型，应当通知用户数据会被清除。

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

## WebSocket

插件可以通过 `RainCurtain.ws` API 创建 WebSocket 服务端（监听端口接受连接）或作为客户端连接远程 WebSocket 服务。支持多实例（同一插件可同时运行多个服务端/客户端），通过 `instanceId` 区分。

### 创建服务端

```javascript
// 创建 WebSocket 服务端，监听指定端口
// port=0 时系统自动分配可用端口
const result = await RainCurtain.ws.createServer({ port: 8765 });
// result = { instanceId: "ws_srv_1", port: 8765 }
// 如果失败: { error: "Address already in use" }

// 可选指定绑定地址（默认 '::' dual-stack，同时接受 IPv4 和 IPv6 连接）
const local = await RainCurtain.ws.createServer({ port: 0, host: '127.0.0.1' });
```

### 连接远程服务

```javascript
// 作为客户端连接远程 WebSocket 服务
const result = await RainCurtain.ws.connect({ url: 'ws://192.168.1.100:8765' });
// result = { instanceId: "ws_cli_1" }
// 如果失败: { error: "Connection timed out" }

// 连接 IPv6 地址（需用方括号包裹）
const result6 = await RainCurtain.ws.connect({ url: 'ws://[fe80::1]:8765' });
```

### 事件监听

所有事件通过 `RainCurtain.ws.on(instanceId, event, callback)` 注册。

```javascript
// === 服务端事件 ===

// 有客户端连入
RainCurtain.ws.on(server.instanceId, 'connection', (clientId, remoteAddress, remotePort) => {
  console.log(`客户端连入: ${clientId} from ${remoteAddress}:${remotePort}`);
});

// 收到客户端文本消息
RainCurtain.ws.on(server.instanceId, 'message', (clientId, data) => {
  console.log(`收到消息: ${data} from ${clientId}`);
});

// 收到客户端二进制消息
RainCurtain.ws.on(server.instanceId, 'binary', (clientId, arrayBuffer) => {
  const bytes = new Uint8Array(arrayBuffer);
  console.log(`收到二进制: ${bytes.length} bytes from ${clientId}`);
});

// 客户端断开
RainCurtain.ws.on(server.instanceId, 'disconnect', (clientId, code, reason) => {
  console.log(`客户端断开: ${clientId}, code=${code}`);
});

// 服务端错误
RainCurtain.ws.on(server.instanceId, 'error', (message) => {
  console.error(`服务端错误: ${message}`);
});

// === 客户端事件 ===

// 连接成功
RainCurtain.ws.on(conn.instanceId, 'open', () => {
  console.log('连接成功');
});

// 收到文本消息
RainCurtain.ws.on(conn.instanceId, 'message', (data) => {
  console.log(`收到: ${data}`);
});

// 收到二进制消息
RainCurtain.ws.on(conn.instanceId, 'binary', (arrayBuffer) => {
  const bytes = new Uint8Array(arrayBuffer);
});

// 连接关闭
RainCurtain.ws.on(conn.instanceId, 'close', (code, reason) => {
  console.log(`连接关闭: code=${code}, reason=${reason}`);
});

// 连接错误
RainCurtain.ws.on(conn.instanceId, 'error', (message) => {
  console.error(`连接错误: ${message}`);
});
```

### 发送消息

```javascript
// === 服务端：向指定客户端发送 ===

// 发送文本
await RainCurtain.ws.send(server.instanceId, clientId, '{"type":"hello"}');

// 发送二进制（ArrayBuffer）
const buffer = new TextEncoder().encode('binary data').buffer;
await RainCurtain.ws.sendBinary(server.instanceId, clientId, buffer);

// 广播文本给所有已连接客户端
await RainCurtain.ws.broadcast(server.instanceId, '{"type":"announcement"}');

// 广播二进制
await RainCurtain.ws.broadcastBinary(server.instanceId, buffer);

// === 客户端：向服务端发送 ===

// 发送文本（clientId 传 null）
await RainCurtain.ws.send(conn.instanceId, null, '{"type":"move","x":3,"y":5}');

// 发送二进制
await RainCurtain.ws.sendBinary(conn.instanceId, null, buffer);
```

### 管理连接

```javascript
// 获取服务端已连接客户端列表
const result = await RainCurtain.ws.getClients(server.instanceId);
// result = { clients: [{ clientId: "cli_1", remoteAddress: "192.168.1.5", remotePort: 54321 }] }

// 断开指定客户端（可选 close code 和 reason）
await RainCurtain.ws.disconnectClient(server.instanceId, clientId, 1000, 'kicked');

// 关闭整个服务端（会断开所有客户端）
await RainCurtain.ws.closeServer(server.instanceId);

// 关闭客户端连接
await RainCurtain.ws.closeClient(conn.instanceId, 1000, 'bye');
```

### 辅助方法

```javascript
// 获取本机局域网 IPv4 地址（用于告知对方连接地址）
const ip = await RainCurtain.ws.getLocalIP();
// ip = "192.168.1.100"

// 获取本机局域网 IPv6 地址（优先 ULA，其次 link-local）
const ipv6 = await RainCurtain.ws.getLocalIPv6();
// ipv6 = "fd12:3456:789a::1" 或 "fe80::abcd:1234" 或 null（无可用 IPv6）

// 获取所有可用局域网 IP（IPv4 + IPv6）
const ips = await RainCurtain.ws.getLocalIPs();
// ips = { ipv4: "192.168.1.100", ipv6: "fd12:3456:789a::1" }
// 如果无 IPv6: { ipv4: "192.168.1.100", ipv6: null }

// 获取所有活跃 WebSocket 实例
const instances = await RainCurtain.ws.getInstances();
// instances = [
//   { instanceId: "ws_srv_1", type: "server", port: 8765, clientCount: 2 },
//   { instanceId: "ws_cli_1", type: "client", url: "ws://..." }
// ]
```

### 移除事件监听

```javascript
// 移除特定回调
RainCurtain.ws.off(instanceId, 'message', myCallback);

// 移除某事件的所有监听（不传 callback）
RainCurtain.ws.off(instanceId, 'message');
```

### 完整示例：简易聊天

```javascript
// === 房主（服务端）===
async function hostRoom() {
  const server = await RainCurtain.ws.createServer({ port: 9000 });
  if (server.error) { alert(server.error); return; }
  
  const ip = await RainCurtain.ws.getLocalIP();
  console.log(`房间已创建，告诉对方连接: ${ip}:${server.port}`);
  
  RainCurtain.ws.on(server.instanceId, 'connection', (clientId) => {
    console.log('对方已加入');
    RainCurtain.ws.send(server.instanceId, clientId, JSON.stringify({ type: 'welcome' }));
  });
  
  RainCurtain.ws.on(server.instanceId, 'message', (clientId, data) => {
    const msg = JSON.parse(data);
    handleMessage(msg);
  });
}

// === 加入者（客户端）===
async function joinRoom(ip, port) {
  // IPv6 地址需用方括号包裹，如 ws://[fe80::1]:9000
  const host = ip.includes(':') ? `[${ip}]` : ip;
  const conn = await RainCurtain.ws.connect({ url: `ws://${host}:${port}` });
  if (conn.error) { alert(conn.error); return; }
  
  RainCurtain.ws.on(conn.instanceId, 'message', (data) => {
    const msg = JSON.parse(data);
    handleMessage(msg);
  });
  
  RainCurtain.ws.on(conn.instanceId, 'close', (code, reason) => {
    console.log('连接已断开');
  });
  
  // 发送消息
  await RainCurtain.ws.send(conn.instanceId, null, JSON.stringify({ type: 'hello' }));
}
```

### 注意事项

- **端口范围**：服务端端口必须在 1024-65535 之间（或传 0 自动分配）
- **资源限制**：单个插件最多创建 5 个服务端 + 10 个客户端实例
- **连接超时**：客户端连接超时为 10 秒
- **自动清理**：插件页面关闭时，所有 WebSocket 连接和服务端自动关闭
- **认证**：系统不内置认证，如需密码验证请在应用层自行实现（如连接后第一条消息进行握手）
- **二进制传输**：通过 base64 编码在内部传输，大量二进制数据（>10MB）可能有性能影响
- **绑定地址**：默认绑定 `::` (dual-stack，同时接受 IPv4 和 IPv6 连接)，如仅需本机通信可指定 `host: '127.0.0.1'` 或 `host: '::1'`
- **IPv6 支持**：服务端默认支持 IPv6 连接；客户端连接 IPv6 地址时需用方括号包裹，如 `ws://[fe80::1]:8765`
- **IPv6 回退**：在极少数不支持 IPv6 的环境下，服务端会自动回退到 `0.0.0.0`（仅 IPv4）

---

## UDP 数据报

插件可以通过 `RainCurtain.udp` API 绑定 UDP socket 收发数据报。支持单播、广播和组播，适用于游戏实时通信、局域网房间发现等低延迟场景。UDP 是无连接协议，不像 WebSocket 有 server/client 区分，直接 bind 一个 socket 即可收发。

### 绑定 Socket

```javascript
// 绑定 UDP socket，开始接收数据报
// port=0 时系统自动分配端口
// host 默认 '0.0.0.0'（接收所有网卡的数据）
const result = await RainCurtain.udp.bind({ port: 9000 });
// result = { instanceId: "udp_1", port: 9000 }
// 失败: { error: "Address already in use" }

// 绑定时可选开启广播
const result = await RainCurtain.udp.bind({ port: 9000, broadcast: true });

// 仅发送（不绑定接收端口，系统分配临时端口）
const result = await RainCurtain.udp.bind({ port: 0 });
```

### 发送数据

```javascript
// 发送文本数据报到指定地址
await RainCurtain.udp.send(instanceId, address, port, textData);

// 发送二进制数据报（ArrayBuffer）
await RainCurtain.udp.sendBinary(instanceId, address, port, arrayBuffer);

// 广播（需要 bind 时 broadcast: true）
await RainCurtain.udp.send(instanceId, '255.255.255.255', 9000, data);
// 或子网广播
await RainCurtain.udp.send(instanceId, '192.168.1.255', 9000, data);
```

### 事件监听

所有事件通过 `RainCurtain.udp.on(instanceId, event, callback)` 注册。

```javascript
// 收到数据报
// data 参数类型：可 UTF-8 解码时为 string，否则为 ArrayBuffer
RainCurtain.udp.on(result.instanceId, 'message', (data, remoteAddress, remotePort) => {
  if (typeof data === 'string') {
    console.log(`收到文本: ${data} from ${remoteAddress}:${remotePort}`);
  } else {
    // data 是 ArrayBuffer
    const bytes = new Uint8Array(data);
    console.log(`收到二进制: ${bytes.length} bytes from ${remoteAddress}:${remotePort}`);
  }
});

// 错误
RainCurtain.udp.on(result.instanceId, 'error', (message) => {
  console.error(`UDP 错误: ${message}`);
});

// Socket 关闭
RainCurtain.udp.on(result.instanceId, 'close', () => {
  console.log('Socket 已关闭');
});
```

### 组播

```javascript
// 加入组播组（地址范围 224.0.0.0 - 239.255.255.255）
await RainCurtain.udp.joinMulticast(instanceId, '239.1.2.3');

// 发送到组播地址
await RainCurtain.udp.send(instanceId, '239.1.2.3', 9000, data);

// 离开组播组
await RainCurtain.udp.leaveMulticast(instanceId, '239.1.2.3');
```

### 管理

```javascript
// 关闭 socket
await RainCurtain.udp.close(instanceId);

// 设置广播开关（绑定后也可更改）
await RainCurtain.udp.setBroadcast(instanceId, true);

// 获取所有活跃 UDP 实例
const instances = await RainCurtain.udp.getInstances();
// instances = [{ instanceId: "udp_1", port: 9000, address: "0.0.0.0" }, ...]

// 移除事件监听
RainCurtain.udp.off(instanceId, 'message', myCallback);
// 移除某事件所有监听（不传 callback）
RainCurtain.udp.off(instanceId, 'message');
```

### 完整示例：局域网房间发现（广播）

```javascript
// === 服务端：绑定端口，等待发现请求 ===
async function hostRoom() {
  const server = await RainCurtain.udp.bind({ port: 9000, broadcast: true });
  if (server.error) { alert(server.error); return; }

  RainCurtain.udp.on(server.instanceId, 'message', (data, addr, port) => {
    if (data === 'DISCOVER') {
      RainCurtain.udp.send(server.instanceId, addr, port,
        JSON.stringify({ name: '我的房间', players: 1 }));
    }
  });
}

// === 客户端：广播发现请求 ===
async function discoverRooms() {
  const client = await RainCurtain.udp.bind({ port: 0, broadcast: true });
  if (client.error) { alert(client.error); return; }

  RainCurtain.udp.on(client.instanceId, 'message', (data, addr, port) => {
    const room = JSON.parse(data);
    console.log(`发现房间: ${room.name} at ${addr}:${port}`);
  });

  await RainCurtain.udp.send(client.instanceId, '255.255.255.255', 9000, 'DISCOVER');
}
```

### 注意事项

- **端口范围**：绑定端口必须在 1024-65535 之间（或传 0 自动分配）
- **资源限制**：单个插件最多 10 个 UDP socket 实例
- **自动清理**：插件页面关闭时，所有 UDP socket 自动关闭
- **无连接**：UDP 不保证送达和顺序，适合实时性要求高、可容忍丢包的场景
- **广播**：发送到 `255.255.255.255` 或子网广播地址前，需确保 `broadcast: true`
- **组播地址**：必须在 224.0.0.0 - 239.255.255.255 范围内
- **数据大小**：单个 UDP 数据报建议不超过 MTU（通常 1472 bytes），超大数据报可能被分片或丢弃
- **绑定地址**：默认绑定 `0.0.0.0`（IPv4 any），广播仅在 IPv4 下有效
- **与 WebSocket 关系**：UDP 和 WebSocket 是独立 API，可同时使用。WS 适合可靠有序传输，UDP 适合低延迟实时数据

---

## DNS 解析

插件可以通过 `RainCurtain.dns` API 执行 DNS 域名解析。支持多种记录类型（A、AAAA、MX、CNAME、TXT、NS、SRV、PTR）、自定义 DNS 服务器和批量解析。底层通过纯 Dart 实现 DNS 协议（RFC 1035），直接发送 UDP 报文到 DNS 服务器的 53 端口。

### 单域名解析

```javascript
// 基础 A 记录查询
const result = await RainCurtain.dns.resolve('google.com');
// result = {
//   domain: "google.com",
//   type: "A",
//   server: "8.8.8.8",
//   timeMs: 23,
//   records: [{ address: "142.250.80.46", ttl: 300 }]
// }

// 指定记录类型和 DNS 服务器
const mx = await RainCurtain.dns.resolve('gmail.com', {
  type: 'MX',
  server: '1.1.1.1'
});
// mx = {
//   domain: "gmail.com", type: "MX", server: "1.1.1.1", timeMs: 35,
//   records: [{ priority: 5, exchange: "gmail-smtp-in.l.google.com", ttl: 3600 }]
// }

// 查询 AAAA 记录（IPv6）
const ipv6 = await RainCurtain.dns.resolve('google.com', { type: 'AAAA' });

// 查询 TXT 记录（SPF、DKIM 等）
const txt = await RainCurtain.dns.resolve('google.com', { type: 'TXT' });
// records: [{ text: "v=spf1 include:_spf.google.com ~all", ttl: 3600 }]

// 查询 CNAME 记录
const cname = await RainCurtain.dns.resolve('www.example.com', { type: 'CNAME' });
// records: [{ name: "example.com", ttl: 300 }]

// 查询 NS 记录
const ns = await RainCurtain.dns.resolve('example.com', { type: 'NS' });
// records: [{ nameserver: "ns1.example.com", ttl: 86400 }]

// 查询 SRV 记录
const srv = await RainCurtain.dns.resolve('_sip._tcp.example.com', { type: 'SRV' });
// records: [{ priority: 10, weight: 60, port: 5060, target: "sip.example.com", ttl: 3600 }]

// 查询 PTR 记录（反向解析）
const ptr = await RainCurtain.dns.resolve('34.216.184.93.in-addr.arpa', { type: 'PTR' });
// records: [{ name: "example.com", ttl: 3600 }]
```

### 选项参数

```javascript
const result = await RainCurtain.dns.resolve(domain, {
  type: 'A',        // 记录类型: A, AAAA, MX, CNAME, TXT, NS, SRV, PTR（默认 'A'）
  server: null,     // 自定义 DNS 服务器地址（默认 '8.8.8.8'）
  port: 53,         // DNS 服务器端口（默认 53）
  timeout: 5000     // 超时时间 ms（默认 5000，最大 30000）
});
```

### 批量解析

```javascript
const batch = await RainCurtain.dns.resolveAll([
  { domain: 'google.com', type: 'A' },
  { domain: 'github.com', type: 'AAAA' },
  { domain: 'gmail.com', type: 'MX' },
], {
  server: '8.8.8.8',   // 全局 DNS 服务器
  concurrency: 3,       // 并发数（默认 5，最大 10）
  timeout: 5000         // 每个查询的超时时间
});
// batch = {
//   totalTimeMs: 156,
//   results: [
//     { domain: "google.com", type: "A", records: [...] },
//     { domain: "github.com", type: "AAAA", records: [...] },
//     { domain: "gmail.com", type: "MX", records: [...] }
//   ]
// }

// 部分失败不影响其他查询
// results: [
//   { domain: "valid.com", type: "A", records: [...] },
//   { domain: "invalid.xxx", type: "A", error: "NXDOMAIN" }
// ]
```

### 错误处理

```javascript
const result = await RainCurtain.dns.resolve('nonexistent.invalid');
if (result.error) {
  console.error(result.error);
  // 可能的错误:
  // "NXDOMAIN"          — 域名不存在
  // "SERVFAIL"          — DNS 服务器内部错误
  // "REFUSED"           — DNS 服务器拒绝查询
  // "Query timed out"   — 查询超时
  // "Invalid domain format" — 域名格式无效
  // "Unsupported record type: XXX" — 不支持的记录类型
  // "Network error: ..."  — 网络连接失败
}
```

### 完整示例：DNS 查询工具

```javascript
async function lookupDomain(domain) {
  // 查询 A 和 AAAA 记录
  const batch = await RainCurtain.dns.resolveAll([
    { domain, type: 'A' },
    { domain, type: 'AAAA' },
    { domain, type: 'MX' },
    { domain, type: 'NS' },
    { domain, type: 'TXT' },
  ], { server: '8.8.8.8', concurrency: 5 });

  for (const result of batch.results) {
    if (result.error) {
      console.log(`${result.type}: ${result.error}`);
    } else {
      console.log(`${result.type}: ${JSON.stringify(result.records)}`);
    }
  }
  console.log(`总耗时: ${batch.totalTimeMs}ms`);
}

lookupDomain('example.com');
```

### 注意事项

- **无需事件监听**：DNS 是纯请求-响应模式，不需要 `on/off` 事件机制
- **默认服务器**：未指定 `server` 时默认使用 Google DNS (8.8.8.8)
- **批量限制**：单次 `resolveAll` 最多 50 个查询
- **并发控制**：`concurrency` 范围 1-10，控制同时发送的 UDP 请求数
- **超时**：单个查询最大超时 30 秒（默认 5 秒）
- **自动清理**：DNS 查询是无状态的，不持有长期资源，无需手动关闭
- **记录类型**：仅支持 A、AAAA、MX、CNAME、TXT、NS、SRV、PTR
- **TTL**：每条记录包含 `ttl` 字段（秒），表示 DNS 缓存有效期

---

## 文件系统访问

File System Access API（`showSaveFilePicker`、`showOpenFilePicker`、`showDirectoryPicker`）已由系统透明代理，直接使用标准浏览器 API 即可。两个平台（Windows / Android）行为一致，底层通过 Flutter 的 `file_picker` 包实现。

### 保存文件

```javascript
const handle = await window.showSaveFilePicker({
  suggestedName: 'data.json',
  types: [{
    description: 'JSON 文件',
    accept: { 'application/json': ['.json'] }
  }]
});
const writable = await handle.createWritable();
await writable.write(JSON.stringify(data, null, 2));
await writable.close();
```

### 打开文件

```javascript
// 选择单个文件
const [handle] = await window.showOpenFilePicker({
  types: [{
    description: '图片',
    accept: { 'image/*': ['.png', '.jpg', '.jpeg', '.gif', '.webp'] }
  }]
});
const file = await handle.getFile();
const text = await file.text();
// 或读取为 ArrayBuffer
const buffer = await file.arrayBuffer();

// 选择多个文件
const handles = await window.showOpenFilePicker({ multiple: true });
for (const h of handles) {
  const f = await h.getFile();
  console.log(f.name, f.size);
}
```

### 选择目录

```javascript
const dirHandle = await window.showDirectoryPicker();

// 遍历目录
for await (const [name, handle] of dirHandle.entries()) {
  console.log(name, handle.kind); // 'file' 或 'directory'
}

// 获取子文件
const fileHandle = await dirHandle.getFileHandle('config.json');
const file = await fileHandle.getFile();

// 创建子文件
const newFile = await dirHandle.getFileHandle('output.txt', { create: true });
const w = await newFile.createWritable();
await w.write('Hello');
await w.close();

// 创建子目录
const subDir = await dirHandle.getDirectoryHandle('subdir', { create: true });

// 删除条目
await dirHandle.removeEntry('temp.txt');
await dirHandle.removeEntry('old_dir', { recursive: true });
```

### 注意事项

- 用户取消选择器时，会抛出 `DOMException`（name = `'AbortError'`），需用 try/catch 捕获
- `FileSystemWritableFileStream.write()` 支持 `string`、`Blob`、`ArrayBuffer`、`TypedArray` 和 `WriteParams` 对象
- 所有文件内容通过 base64 在 JS↔Flutter 间传输，超大文件（>100MB）可能有性能影响
- `queryPermission()` 和 `requestPermission()` 始终返回 `'granted'`

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
- 文件系统访问 (`window.showOpenFilePicker()` / `window.showSaveFilePicker()` / `window.showDirectoryPicker()`) — 已由系统透明代理，直接使用标准 API 即可，两个平台行为一致
- USB、串口、MIDI、传感器、字体枚举

---

## 屏幕方向控制

插件可以通过 `RainCurtain.orientation` API 控制屏幕方向。调用后 **Android 系统真正旋转屏幕**（状态栏、键盘、输入法等全部跟随），属于系统级旋转。此 API 仅在插件页面生效，插件页面关闭时自动恢复为自由旋转。Windows 平台调用无副作用。

### 切换为横屏

```javascript
// 系统级横屏：状态栏到侧边，键盘横向弹出
const result = await RainCurtain.orientation.lock('landscape');
// result = { success: true }
```

### 恢复竖屏

```javascript
// 锁定为竖屏
const result = await RainCurtain.orientation.lock('portrait');

// 或解锁为自由旋转（跟随系统自动旋转设置）
const result = await RainCurtain.orientation.unlock();
// result = { success: true }
```

### 查询当前状态

```javascript
const info = await RainCurtain.orientation.get();
// 横屏锁定时:
// info = { mode: 'landscape', locked: true }

// 未锁定时（默认）:
// info = { mode: 'portrait', locked: false }
```

### 错误处理

```javascript
const result = await RainCurtain.orientation.lock('invalid');
if (!result.success) {
  console.error(result.error);
  // "mode must be 'landscape' or 'portrait'"
}
```

### 完整示例：视频播放器横屏

```javascript
// 进入全屏播放时横屏
async function enterFullscreen() {
  await RainCurtain.orientation.lock('landscape');
  document.querySelector('.video-player').classList.add('fullscreen');
}

// 退出全屏时恢复
async function exitFullscreen() {
  await RainCurtain.orientation.unlock();
  document.querySelector('.video-player').classList.remove('fullscreen');
}
```

### 注意事项

- **系统级旋转**：通过 `SystemChrome.setPreferredOrientations` 实现，Android 系统真正切换屏幕方向，键盘、输入法、状态栏等全部跟随旋转
- **插件级生效**：方向锁定仅在当前插件页面有效，插件页面关闭（dispose）时自动恢复为自由旋转
- **Windows 兼容**：Windows 平台调用 API 返回 success 但无视觉效果（桌面端无旋转概念）
- **两种模式**：`'landscape'`（横屏，含左旋和右旋）和 `'portrait'`（竖屏，含正向和反向）
- **`unlock()` vs `lock('portrait')`**：`unlock()` 恢复为自由旋转（跟随系统自动旋转设置），`lock('portrait')` 强制锁定竖屏（禁止旋转到横屏）
