# UDP 数据报参考

插件可以通过 `RainCurtain.udp` API 绑定 UDP socket 收发数据报。支持单播、广播和组播，适用于游戏实时通信、局域网房间发现等低延迟场景。UDP 是无连接协议，不像 WebSocket 有 server/client 区分，直接 bind 一个 socket 即可收发。

## 绑定 Socket

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

## 发送数据

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

## 事件监听

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

## 组播

```javascript
// 加入组播组（地址范围 224.0.0.0 - 239.255.255.255）
await RainCurtain.udp.joinMulticast(instanceId, '239.1.2.3');

// 发送到组播地址
await RainCurtain.udp.send(instanceId, '239.1.2.3', 9000, data);

// 离开组播组
await RainCurtain.udp.leaveMulticast(instanceId, '239.1.2.3');
```

## 管理

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

## 完整示例：局域网房间发现（广播）

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

## 注意事项

- **端口范围**：绑定端口必须在 1024-65535 之间（或传 0 自动分配）
- **资源限制**：单个插件最多 10 个 UDP socket 实例
- **自动清理**：插件页面关闭时，所有 UDP socket 自动关闭
- **无连接**：UDP 不保证送达和顺序，适合实时性要求高、可容忍丢包的场景
- **广播**：发送到 `255.255.255.255` 或子网广播地址前，需确保 `broadcast: true`
- **组播地址**：必须在 224.0.0.0 - 239.255.255.255 范围内
- **数据大小**：单个 UDP 数据报建议不超过 MTU（通常 1472 bytes），超大数据报可能被分片或丢弃
- **绑定地址**：默认绑定 `0.0.0.0`（IPv4 any），广播仅在 IPv4 下有效
- **与 WebSocket 关系**：UDP 和 WebSocket 是独立 API，可同时使用。WS 适合可靠有序传输，UDP 适合低延迟实时数据
