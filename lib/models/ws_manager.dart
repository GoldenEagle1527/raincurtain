import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// WebSocket 服务端实例
class WsServerInstance {
  final String instanceId;
  final HttpServer httpServer;
  final int port;
  final Map<String, WebSocket> clients = {};
  final Map<String, String> clientAddresses = {};
  final Map<String, int> clientPorts = {};
  int _clientCounter = 0;
  StreamSubscription? _subscription;

  WsServerInstance({
    required this.instanceId,
    required this.httpServer,
    required this.port,
  });

  String nextClientId() => 'cli_${++_clientCounter}';
}

/// WebSocket 客户端实例
class WsClientInstance {
  final String instanceId;
  final WebSocket webSocket;
  final String url;
  StreamSubscription? _subscription;

  WsClientInstance({
    required this.instanceId,
    required this.webSocket,
    required this.url,
  });
}

/// 事件回调类型
/// (instanceId, eventName, payload)
typedef WsEventCallback = void Function(
    String instanceId, String event, Map<String, dynamic> payload);

/// WebSocket 管理器
/// 管理一个插件 WebView 的所有 WebSocket 服务端和客户端实例
class WsManager {
  final WsEventCallback onEvent;

  final Map<String, WsServerInstance> _servers = {};
  final Map<String, WsClientInstance> _clients = {};
  int _instanceCounter = 0;

  /// 资源限制
  static const int maxServers = 5;
  static const int maxClients = 10;

  WsManager({required this.onEvent});

  String _nextInstanceId(String prefix) => '${prefix}_${++_instanceCounter}';

  // ==================== 服务端 API ====================

  /// 创建 WebSocket 服务端
  /// [port] 监听端口，0 表示系统自动分配
  /// [host] 绑定地址，默认 '0.0.0.0'（允许局域网连接）
  Future<Map<String, dynamic>> createServer({
    int port = 0,
    String host = '0.0.0.0',
  }) async {
    if (_servers.length >= maxServers) {
      return {'error': 'Max server limit reached ($maxServers)'};
    }

    // 端口范围检查（0 为自动分配，1024-65535 为有效范围）
    if (port != 0 && (port < 1024 || port > 65535)) {
      return {'error': 'Port must be 0 (auto) or between 1024 and 65535'};
    }

    try {
      final server = await HttpServer.bind(host, port);
      final actualPort = server.port;
      final instanceId = _nextInstanceId('ws_srv');

      final instance = WsServerInstance(
        instanceId: instanceId,
        httpServer: server,
        port: actualPort,
      );

      // 监听 HTTP 升级请求
      instance._subscription = server.listen(
        (HttpRequest request) async {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            try {
              final ws = await WebSocketTransformer.upgrade(request);
              _handleNewClient(instance, ws, request);
            } catch (e) {
              debugPrint('[WsManager] WebSocket upgrade failed: $e');
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..close();
            }
          } else {
            // 非 WebSocket 请求，返回 426
            request.response
              ..statusCode = HttpStatus.upgradeRequired
              ..headers.set('Upgrade', 'websocket')
              ..write('WebSocket upgrade required')
              ..close();
          }
        },
        onError: (e) {
          debugPrint('[WsManager] Server error on $instanceId: $e');
          onEvent(instanceId, 'error', {'message': e.toString()});
        },
        onDone: () {
          debugPrint('[WsManager] Server $instanceId closed');
        },
      );

      _servers[instanceId] = instance;
      debugPrint(
          '[WsManager] Server created: $instanceId on port $actualPort');
      return {'instanceId': instanceId, 'port': actualPort};
    } catch (e) {
      debugPrint('[WsManager] Failed to create server: $e');
      return {'error': e.toString()};
    }
  }

  /// 处理新客户端连接
  void _handleNewClient(
      WsServerInstance instance, WebSocket ws, HttpRequest request) {
    final clientId = instance.nextClientId();
    final remoteAddress =
        request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final remotePort = request.connectionInfo?.remotePort ?? 0;

    instance.clients[clientId] = ws;
    instance.clientAddresses[clientId] = remoteAddress;
    instance.clientPorts[clientId] = remotePort;

    debugPrint(
        '[WsManager] Client connected: $clientId ($remoteAddress:$remotePort) to ${instance.instanceId}');

    // 通知插件有新连接
    onEvent(instance.instanceId, 'connection', {
      'clientId': clientId,
      'remoteAddress': remoteAddress,
      'remotePort': remotePort,
    });

    // 监听客户端消息
    ws.listen(
      (data) {
        if (data is String) {
          onEvent(instance.instanceId, 'message', {
            'clientId': clientId,
            'data': data,
          });
        } else if (data is List<int>) {
          final b64 = base64Encode(data);
          onEvent(instance.instanceId, 'binary', {
            'clientId': clientId,
            'data': b64,
          });
        }
      },
      onDone: () {
        instance.clients.remove(clientId);
        instance.clientAddresses.remove(clientId);
        instance.clientPorts.remove(clientId);
        onEvent(instance.instanceId, 'disconnect', {
          'clientId': clientId,
          'code': ws.closeCode ?? 1000,
          'reason': ws.closeReason ?? '',
        });
        debugPrint(
            '[WsManager] Client disconnected: $clientId from ${instance.instanceId}');
      },
      onError: (e) {
        debugPrint(
            '[WsManager] Client error on $clientId: $e');
        onEvent(instance.instanceId, 'error', {
          'clientId': clientId,
          'message': e.toString(),
        });
      },
    );
  }

  /// 向服务端的指定客户端发送文本消息
  Map<String, dynamic>? sendToClient(
      String instanceId, String clientId, String data) {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    final ws = server.clients[clientId];
    if (ws == null) return {'error': 'Client not found'};
    if (ws.readyState != WebSocket.open) {
      return {'error': 'Client connection not open'};
    }
    try {
      ws.add(data);
      return null; // success
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 向服务端的指定客户端发送二进制消息
  Map<String, dynamic>? sendBinaryToClient(
      String instanceId, String clientId, Uint8List bytes) {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    final ws = server.clients[clientId];
    if (ws == null) return {'error': 'Client not found'};
    if (ws.readyState != WebSocket.open) {
      return {'error': 'Client connection not open'};
    }
    try {
      ws.add(bytes);
      return null; // success
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 广播文本消息给服务端所有已连接客户端
  Map<String, dynamic>? broadcast(String instanceId, String data) {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    for (final ws in server.clients.values) {
      if (ws.readyState == WebSocket.open) {
        try {
          ws.add(data);
        } catch (e) {
          debugPrint('[WsManager] Broadcast send error: $e');
        }
      }
    }
    return null;
  }

  /// 广播二进制消息给服务端所有已连接客户端
  Map<String, dynamic>? broadcastBinary(String instanceId, Uint8List bytes) {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    for (final ws in server.clients.values) {
      if (ws.readyState == WebSocket.open) {
        try {
          ws.add(bytes);
        } catch (e) {
          debugPrint('[WsManager] Broadcast binary send error: $e');
        }
      }
    }
    return null;
  }

  /// 断开服务端的指定客户端
  Future<Map<String, dynamic>?> disconnectClient(
      String instanceId, String clientId,
      [int? code, String? reason]) async {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    final ws = server.clients[clientId];
    if (ws == null) return {'error': 'Client not found'};
    try {
      await ws.close(code ?? 1000, reason ?? '');
      server.clients.remove(clientId);
      server.clientAddresses.remove(clientId);
      server.clientPorts.remove(clientId);
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 关闭服务端实例
  Future<Map<String, dynamic>?> closeServer(String instanceId) async {
    final server = _servers.remove(instanceId);
    if (server == null) return {'error': 'Server instance not found'};
    try {
      // 关闭所有客户端连接
      for (final ws in server.clients.values) {
        try {
          await ws.close(1001, 'Server shutting down');
        } catch (_) {}
      }
      server.clients.clear();
      server.clientAddresses.clear();
      server.clientPorts.clear();
      // 取消监听
      await server._subscription?.cancel();
      // 关闭 HTTP 服务器
      await server.httpServer.close(force: true);
      debugPrint('[WsManager] Server closed: $instanceId');
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 获取服务端已连接客户端列表
  Map<String, dynamic> getClients(String instanceId) {
    final server = _servers[instanceId];
    if (server == null) return {'error': 'Server instance not found'};
    final list = server.clients.keys.map((clientId) {
      return {
        'clientId': clientId,
        'remoteAddress': server.clientAddresses[clientId] ?? 'unknown',
        'remotePort': server.clientPorts[clientId] ?? 0,
      };
    }).toList();
    return {'clients': list};
  }

  // ==================== 客户端 API ====================

  /// 连接到远程 WebSocket 服务端
  /// [url] WebSocket URL，如 'ws://192.168.1.2:8765'
  Future<Map<String, dynamic>> connect({required String url}) async {
    if (_clients.length >= maxClients) {
      return {'error': 'Max client limit reached ($maxClients)'};
    }

    try {
      final ws = await WebSocket.connect(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timed out'),
      );
      final instanceId = _nextInstanceId('ws_cli');

      final instance = WsClientInstance(
        instanceId: instanceId,
        webSocket: ws,
        url: url,
      );

      // 监听消息（先注册监听，再触发 open 事件，避免遗漏消息）
      instance._subscription = ws.listen(
        (data) {
          if (data is String) {
            onEvent(instanceId, 'message', {'data': data});
          } else if (data is List<int>) {
            final b64 = base64Encode(data);
            onEvent(instanceId, 'binary', {'data': b64});
          }
        },
        onDone: () {
          _clients.remove(instanceId);
          onEvent(instanceId, 'close', {
            'code': ws.closeCode ?? 1000,
            'reason': ws.closeReason ?? '',
          });
          debugPrint('[WsManager] Client connection closed: $instanceId');
        },
        onError: (e) {
          debugPrint('[WsManager] Client connection error on $instanceId: $e');
          onEvent(instanceId, 'error', {'message': e.toString()});
        },
      );

      _clients[instanceId] = instance;
      debugPrint('[WsManager] Connected to $url as $instanceId');

      // 'open' 事件同步触发。JS 侧的 __rc_ws_event 有事件缓冲机制，
      // 若 JS 尚未注册监听器，事件会被缓冲，在 on() 注册时自动 flush。
      onEvent(instanceId, 'open', {});

      return {'instanceId': instanceId};
    } on TimeoutException {
      return {'error': 'Connection timed out'};
    } catch (e) {
      debugPrint('[WsManager] Failed to connect to $url: $e');
      return {'error': e.toString()};
    }
  }

  /// 通过客户端实例发送文本消息
  Map<String, dynamic>? sendFromClient(String instanceId, String data) {
    final client = _clients[instanceId];
    if (client == null) return {'error': 'Client instance not found'};
    if (client.webSocket.readyState != WebSocket.open) {
      return {'error': 'Connection not open'};
    }
    try {
      client.webSocket.add(data);
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 通过客户端实例发送二进制消息
  Map<String, dynamic>? sendBinaryFromClient(
      String instanceId, Uint8List bytes) {
    final client = _clients[instanceId];
    if (client == null) return {'error': 'Client instance not found'};
    if (client.webSocket.readyState != WebSocket.open) {
      return {'error': 'Connection not open'};
    }
    try {
      client.webSocket.add(bytes);
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 关闭客户端连接
  Future<Map<String, dynamic>?> closeClient(String instanceId,
      [int? code, String? reason]) async {
    final client = _clients.remove(instanceId);
    if (client == null) return {'error': 'Client instance not found'};
    try {
      await client._subscription?.cancel();
      await client.webSocket.close(code ?? 1000, reason ?? '');
      debugPrint('[WsManager] Client closed: $instanceId');
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ==================== 通用 API ====================

  /// 统一发送接口：根据 instanceId 前缀判断是服务端还是客户端
  Map<String, dynamic>? send(
      String instanceId, String? clientId, String data) {
    if (instanceId.startsWith('ws_srv')) {
      if (clientId == null || clientId.isEmpty) {
        return {'error': 'clientId required for server instance'};
      }
      return sendToClient(instanceId, clientId, data);
    } else if (instanceId.startsWith('ws_cli')) {
      return sendFromClient(instanceId, data);
    }
    return {'error': 'Invalid instance ID'};
  }

  /// 统一二进制发送接口
  Map<String, dynamic>? sendBinary(
      String instanceId, String? clientId, Uint8List bytes) {
    if (instanceId.startsWith('ws_srv')) {
      if (clientId == null || clientId.isEmpty) {
        return {'error': 'clientId required for server instance'};
      }
      return sendBinaryToClient(instanceId, clientId, bytes);
    } else if (instanceId.startsWith('ws_cli')) {
      return sendBinaryFromClient(instanceId, bytes);
    }
    return {'error': 'Invalid instance ID'};
  }

  /// 获取所有活跃实例
  List<Map<String, dynamic>> getInstances() {
    final list = <Map<String, dynamic>>[];
    for (final s in _servers.values) {
      list.add({
        'instanceId': s.instanceId,
        'type': 'server',
        'port': s.port,
        'clientCount': s.clients.length,
      });
    }
    for (final c in _clients.values) {
      list.add({
        'instanceId': c.instanceId,
        'type': 'client',
        'url': c.url,
      });
    }
    return list;
  }

  /// 获取本机局域网 IP
  static Future<String> getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          // 匹配常见局域网地址段
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              _isPrivate172(ip)) {
            return ip;
          }
        }
      }
    } catch (e) {
      debugPrint('[WsManager] Failed to get local IP: $e');
    }
    return '127.0.0.1';
  }

  /// 判断是否为 172.16.0.0 - 172.31.255.255 私有地址段
  static bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    if (second == null) return false;
    return second >= 16 && second <= 31;
  }

  /// 释放所有资源（WebView dispose 时调用）
  Future<void> disposeAll() async {
    debugPrint(
        '[WsManager] Disposing all instances (${_servers.length} servers, ${_clients.length} clients)');

    // 关闭所有客户端
    final clientIds = List<String>.from(_clients.keys);
    for (final id in clientIds) {
      try {
        await closeClient(id, 1001, 'Plugin disposed');
      } catch (_) {}
    }

    // 关闭所有服务端
    final serverIds = List<String>.from(_servers.keys);
    for (final id in serverIds) {
      try {
        await closeServer(id);
      } catch (_) {}
    }
  }
}
