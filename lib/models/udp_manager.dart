import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// UDP Socket 实例
class UdpSocketInstance {
  final String instanceId;
  final RawDatagramSocket socket;
  final int port;
  final String address;
  StreamSubscription<RawSocketEvent>? _subscription;

  UdpSocketInstance({
    required this.instanceId,
    required this.socket,
    required this.port,
    required this.address,
  });
}

/// 事件回调类型（与 WsEventCallback 签名相同）
/// (instanceId, eventName, payload)
typedef UdpEventCallback = void Function(
    String instanceId, String event, Map<String, dynamic> payload);

/// UDP Socket 管理器
/// 管理一个插件 WebView 的所有 UDP socket 实例
class UdpManager {
  final UdpEventCallback onEvent;

  final Map<String, UdpSocketInstance> _sockets = {};
  int _instanceCounter = 0;

  /// 资源限制：单个插件最多 10 个 UDP socket
  static const int maxSockets = 10;

  UdpManager({required this.onEvent});

  String _nextInstanceId() => 'udp_${++_instanceCounter}';

  // ==================== 绑定 ====================

  /// 绑定 UDP socket
  /// [port] 监听端口，0 表示系统自动分配
  /// [host] 绑定地址，默认 '0.0.0.0'（IPv4 any，广播兼容）
  /// [broadcast] 是否开启广播
  Future<Map<String, dynamic>> bind({
    int port = 0,
    String host = '0.0.0.0',
    bool broadcast = false,
  }) async {
    if (_sockets.length >= maxSockets) {
      return {'error': 'Max UDP socket limit reached ($maxSockets)'};
    }

    // 端口范围检查（0 为自动分配，1024-65535 为有效范围）
    if (port != 0 && (port < 1024 || port > 65535)) {
      return {'error': 'Port must be 0 (auto) or between 1024 and 65535'};
    }

    try {
      final socket = await RawDatagramSocket.bind(host, port);
      socket.broadcastEnabled = broadcast;

      final instanceId = _nextInstanceId();
      final actualPort = socket.port;

      final instance = UdpSocketInstance(
        instanceId: instanceId,
        socket: socket,
        port: actualPort,
        address: host,
      );

      // 监听数据报
      instance._subscription = socket.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              // 始终提供 base64 编码的原始字节
              final b64 = base64Encode(datagram.data);
              // 尝试 UTF-8 解码
              String? text;
              try {
                text = utf8.decode(datagram.data);
              } catch (_) {
                // 非 UTF-8 数据，text 保持 null
              }

              onEvent(instanceId, 'message', {
                'data': b64,
                'text': text,
                'address': datagram.address.address,
                'port': datagram.port,
              });
            }
          }
        },
        onError: (e) {
          debugPrint('[UdpManager] Socket error on $instanceId: $e');
          onEvent(instanceId, 'error', {'message': e.toString()});
        },
        onDone: () {
          debugPrint('[UdpManager] Socket $instanceId closed');
          _sockets.remove(instanceId);
          onEvent(instanceId, 'close', {});
        },
      );

      _sockets[instanceId] = instance;
      debugPrint(
          '[UdpManager] Socket bound: $instanceId on $host:$actualPort (broadcast=$broadcast)');
      return {'instanceId': instanceId, 'port': actualPort};
    } catch (e) {
      debugPrint('[UdpManager] Failed to bind: $e');
      return {'error': e.toString()};
    }
  }

  // ==================== 发送 ====================

  /// 发送文本数据报
  Map<String, dynamic>? send(
      String instanceId, String address, int port, String data) {
    final instance = _sockets[instanceId];
    if (instance == null) return {'error': 'Socket not found'};
    try {
      final bytes = utf8.encode(data);
      final sent =
          instance.socket.send(bytes, InternetAddress(address), port);
      return {'sent': sent};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 发送二进制数据报
  Map<String, dynamic>? sendBinary(
      String instanceId, String address, int port, Uint8List bytes) {
    final instance = _sockets[instanceId];
    if (instance == null) return {'error': 'Socket not found'};
    try {
      final sent =
          instance.socket.send(bytes, InternetAddress(address), port);
      return {'sent': sent};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ==================== 广播/组播 ====================

  /// 设置广播开关
  Map<String, dynamic>? setBroadcast(String instanceId, bool enabled) {
    final instance = _sockets[instanceId];
    if (instance == null) return {'error': 'Socket not found'};
    try {
      instance.socket.broadcastEnabled = enabled;
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 加入组播组
  Map<String, dynamic>? joinMulticast(
      String instanceId, String multicastAddress) {
    final instance = _sockets[instanceId];
    if (instance == null) return {'error': 'Socket not found'};
    try {
      instance.socket.joinMulticast(InternetAddress(multicastAddress));
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 离开组播组
  Map<String, dynamic>? leaveMulticast(
      String instanceId, String multicastAddress) {
    final instance = _sockets[instanceId];
    if (instance == null) return {'error': 'Socket not found'};
    try {
      instance.socket.leaveMulticast(InternetAddress(multicastAddress));
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ==================== 管理 ====================

  /// 关闭指定 socket
  Future<Map<String, dynamic>?> close(String instanceId) async {
    final instance = _sockets.remove(instanceId);
    if (instance == null) return {'error': 'Socket not found'};
    try {
      await instance._subscription?.cancel();
      instance.socket.close();
      debugPrint('[UdpManager] Socket closed: $instanceId');
      // 手动触发 close 事件（cancel subscription 后 onDone 不会再触发）
      onEvent(instanceId, 'close', {});
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// 获取所有活跃实例
  List<Map<String, dynamic>> getInstances() {
    return _sockets.values.map((s) {
      return {
        'instanceId': s.instanceId,
        'port': s.port,
        'address': s.address,
      };
    }).toList();
  }

  /// 释放所有资源（WebView dispose 时调用）
  Future<void> disposeAll() async {
    debugPrint(
        '[UdpManager] Disposing all instances (${_sockets.length} sockets)');
    final ids = List<String>.from(_sockets.keys);
    for (final id in ids) {
      try {
        await close(id);
      } catch (_) {}
    }
  }
}
