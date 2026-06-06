# DNS 解析参考

插件可以通过 `RainCurtain.dns` API 执行 DNS 域名解析。支持多种记录类型（A、AAAA、MX、CNAME、TXT、NS、SRV、PTR）、自定义 DNS 服务器和批量解析。底层通过纯 Dart 实现 DNS 协议（RFC 1035），直接发送 UDP 报文到 DNS 服务器的 53 端口。

## 单域名解析

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

## 选项参数

```javascript
const result = await RainCurtain.dns.resolve(domain, {
  type: 'A',        // 记录类型: A, AAAA, MX, CNAME, TXT, NS, SRV, PTR（默认 'A'）
  server: null,     // 自定义 DNS 服务器地址（默认 '8.8.8.8'）
  port: 53,         // DNS 服务器端口（默认 53）
  timeout: 5000     // 超时时间 ms（默认 5000，最大 30000）
});
```

## 批量解析

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

## 错误处理

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

## 完整示例：DNS 查询工具

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

## 注意事项

- **无需事件监听**：DNS 是纯请求-响应模式，不需要 `on/off` 事件机制
- **默认服务器**：未指定 `server` 时默认使用 Google DNS (8.8.8.8)
- **批量限制**：单次 `resolveAll` 最多 50 个查询
- **并发控制**：`concurrency` 范围 1-10，控制同时发送的 UDP 请求数
- **超时**：单个查询最大超时 30 秒（默认 5 秒）
- **自动清理**：DNS 查询是无状态的，不持有长期资源，无需手动关闭
- **记录类型**：仅支持 A、AAAA、MX、CNAME、TXT、NS、SRV、PTR
- **TTL**：每条记录包含 `ttl` 字段（秒），表示 DNS 缓存有效期
