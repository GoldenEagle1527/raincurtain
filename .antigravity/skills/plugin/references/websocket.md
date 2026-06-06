# WebSocket 参考

插件可以通过 `RainCurtain.ws` API 创建 WebSocket 服务端（监听端口接受连接）或作为客户端连接远程 WebSocket 服务。支持多实例（同一插件可同时运行多个服务端/客户端），通过 `instanceId` 区分。

## 创建服务端

```javascript
// 创建 WebSocket 服务端，监听指定端口
// port=0 时系统自动分配可用端口
const result = await RainCurtain.ws.createServer({ port: 8765 });
// result = { instanceId: "ws_srv_1", port: 8765 }
// 如果失败: { error: "Address already in use" }

// 可选指定绑定地址（默认 '::' dual-stack，同时接受 IPv4 和 IPv6 连接）
const local = await RainCurtain.ws.createServer({ port: 0, host: '127.0.0.1' });
```

## 连接远程服务

```javascript
// 作为客户端连接远程 WebSocket 服务
const result = await RainCurtain.ws.connect({ url: 'ws://192.168.1.100:8765' });
// result = { instanceId: "ws_cli_1" }
// 如果失败: { error: "Connection timed out" }

// 连接 IPv6 地址（需用方括号包裹）
const result6 = await RainCurtain.ws.connect({ url: 'ws://[fe80::1]:8765' });
```

## 事件监听

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

## 发送消息

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

## 管理连接

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

## 辅助方法

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

## 移除事件监听

```javascript
// 移除特定回调
RainCurtain.ws.off(instanceId, 'message', myCallback);

// 移除某事件的所有监听（不传 callback）
RainCurtain.ws.off(instanceId, 'message');
```

## 完整示例：简易聊天

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

## 注意事项

- **端口范围**：服务端端口必须在 1024-65535 之间（或传 0 自动分配）
- **资源限制**：单个插件最多创建 5 个服务端 + 10 个客户端实例
- **连接超时**：客户端连接超时为 10 秒
- **自动清理**：插件页面关闭时，所有 WebSocket 连接和服务端自动关闭
- **认证**：系统不内置认证，如需密码验证请在应用层自行实现（如连接后第一条消息进行握手）
- **二进制传输**：通过 base64 编码在内部传输，大量二进制数据（>10MB）可能有性能影响
- **绑定地址**：默认绑定 `::` (dual-stack，同时接受 IPv4 和 IPv6 连接)，如仅需本机通信可指定 `host: '127.0.0.1'` 或 `host: '::1'`
- **IPv6 支持**：服务端默认支持 IPv6 连接；客户端连接 IPv6 地址时需用方括号包裹，如 `ws://[fe80::1]:8765`
- **IPv6 回退**：在极少数不支持 IPv6 的环境下，服务端会自动回退到 `0.0.0.0`（仅 IPv4）
