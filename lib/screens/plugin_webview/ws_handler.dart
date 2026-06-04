import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/ws_manager.dart';

/// WebSocket 相关的 JS polyfill 和 Handler 注册
mixin WebSocketMixin {
  late final WsManager wsManager;

  /// WebSocket API polyfill — 注入 window.RainCurtain.ws
  static const String polyfillJS = r"""
(function() {
  if (window.__rc_ws_patched) return;
  window.__rc_ws_patched = true;

  var _listeners = {}; // instanceId -> { event -> [cb] }
  var _buffer = {};    // instanceId -> [{event, payload}]  事件缓冲

  function _call(handler, args) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(handler, args);
  }

  // 分发单个事件到回调
  function _dispatch(instanceId, event, payload, cbs) {
    var list = cbs.slice();
    for (var i = 0; i < list.length; i++) {
      try {
        switch (event) {
          case 'connection':
            list[i](payload.clientId, payload.remoteAddress, payload.remotePort);
            break;
          case 'message':
            if (payload.clientId) {
              list[i](payload.clientId, payload.data);
            } else {
              list[i](payload.data);
            }
            break;
          case 'binary':
            var raw = atob(payload.data);
            var arr = new Uint8Array(raw.length);
            for (var j = 0; j < raw.length; j++) arr[j] = raw.charCodeAt(j);
            var buf = arr.buffer;
            if (payload.clientId) {
              list[i](payload.clientId, buf);
            } else {
              list[i](buf);
            }
            break;
          case 'disconnect':
            list[i](payload.clientId, payload.code, payload.reason);
            break;
          case 'open':
            list[i]();
            break;
          case 'close':
            list[i](payload.code, payload.reason);
            break;
          case 'error':
            list[i](payload.message);
            break;
          default:
            list[i](payload);
        }
      } catch (e) {
        console.error('[RainCurtain.ws] Event callback error:', event, e);
      }
    }
  }

  // Flutter 侧推送事件的入口
  window.__rc_ws_event = function(instanceId, event, payload) {
    var cbs = _listeners[instanceId] && _listeners[instanceId][event];
    if (cbs && cbs.length > 0) {
      // 有监听器，直接分发
      _dispatch(instanceId, event, payload, cbs);
    } else {
      // 无监听器，缓冲事件（等 on() 注册时 flush）
      if (!_buffer[instanceId]) _buffer[instanceId] = [];
      _buffer[instanceId].push({ event: event, payload: payload });
    }
  };

  // flush 指定 instance 的缓冲事件
  function _flushBuffer(instanceId) {
    var buf = _buffer[instanceId];
    if (!buf || buf.length === 0) return;
    // 取出并清空缓冲（防止 flush 过程中新事件重复处理）
    _buffer[instanceId] = [];
    for (var i = 0; i < buf.length; i++) {
      var ev = buf[i];
      var cbs = _listeners[instanceId] && _listeners[instanceId][ev.event];
      if (cbs && cbs.length > 0) {
        _dispatch(instanceId, ev.event, ev.payload, cbs);
      } else {
        // 仍然没有对应监听器，放回缓冲
        if (!_buffer[instanceId]) _buffer[instanceId] = [];
        _buffer[instanceId].push(ev);
      }
    }
  }

  // 确保 RainCurtain 对象存在（此脚本在 RainCurtain API 之后注入）
  if (!window.RainCurtain) window.RainCurtain = {};

  window.RainCurtain.ws = {
    createServer: async function(options) {
      try {
        return await _call('rc_ws_create_server', options || {});
      } catch (e) {
        console.error('RainCurtain.ws.createServer error:', e);
        return { error: e.message || String(e) };
      }
    },

    connect: async function(options) {
      try {
        return await _call('rc_ws_connect', options || {});
      } catch (e) {
        console.error('RainCurtain.ws.connect error:', e);
        return { error: e.message || String(e) };
      }
    },

    send: async function(instanceId, clientId, data) {
      try {
        return await _call('rc_ws_send', { instanceId: instanceId, clientId: clientId, data: data });
      } catch (e) {
        console.error('RainCurtain.ws.send error:', e);
        return { error: e.message || String(e) };
      }
    },

    sendBinary: async function(instanceId, clientId, arrayBuffer) {
      try {
        var bytes = new Uint8Array(arrayBuffer);
        var binary = '';
        for (var i = 0; i < bytes.length; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        var base64 = btoa(binary);
        return await _call('rc_ws_send_binary', { instanceId: instanceId, clientId: clientId, data: base64 });
      } catch (e) {
        console.error('RainCurtain.ws.sendBinary error:', e);
        return { error: e.message || String(e) };
      }
    },

    broadcast: async function(instanceId, data) {
      try {
        return await _call('rc_ws_broadcast', { instanceId: instanceId, data: data });
      } catch (e) {
        console.error('RainCurtain.ws.broadcast error:', e);
        return { error: e.message || String(e) };
      }
    },

    broadcastBinary: async function(instanceId, arrayBuffer) {
      try {
        var bytes = new Uint8Array(arrayBuffer);
        var binary = '';
        for (var i = 0; i < bytes.length; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        var base64 = btoa(binary);
        return await _call('rc_ws_broadcast_binary', { instanceId: instanceId, data: base64 });
      } catch (e) {
        console.error('RainCurtain.ws.broadcastBinary error:', e);
        return { error: e.message || String(e) };
      }
    },

    disconnectClient: async function(instanceId, clientId, code, reason) {
      try {
        return await _call('rc_ws_disconnect_client', {
          instanceId: instanceId, clientId: clientId, code: code, reason: reason
        });
      } catch (e) {
        console.error('RainCurtain.ws.disconnectClient error:', e);
        return { error: e.message || String(e) };
      }
    },

    closeServer: async function(instanceId) {
      try {
        delete _listeners[instanceId];
        delete _buffer[instanceId];
        return await _call('rc_ws_close_server', { instanceId: instanceId });
      } catch (e) {
        console.error('RainCurtain.ws.closeServer error:', e);
        return { error: e.message || String(e) };
      }
    },

    closeClient: async function(instanceId, code, reason) {
      try {
        delete _listeners[instanceId];
        delete _buffer[instanceId];
        return await _call('rc_ws_close_client', { instanceId: instanceId, code: code, reason: reason });
      } catch (e) {
        console.error('RainCurtain.ws.closeClient error:', e);
        return { error: e.message || String(e) };
      }
    },

    getClients: async function(instanceId) {
      try {
        return await _call('rc_ws_get_clients', { instanceId: instanceId });
      } catch (e) {
        console.error('RainCurtain.ws.getClients error:', e);
        return { error: e.message || String(e) };
      }
    },

    getLocalIP: async function() {
      try {
        return await _call('rc_ws_get_local_ip', {});
      } catch (e) {
        console.error('RainCurtain.ws.getLocalIP error:', e);
        return '127.0.0.1';
      }
    },

    getLocalIPv6: async function() {
      try {
        return await _call('rc_ws_get_local_ipv6', {});
      } catch (e) {
        console.error('RainCurtain.ws.getLocalIPv6 error:', e);
        return null;
      }
    },

    getLocalIPs: async function() {
      try {
        return await _call('rc_ws_get_local_ips', {});
      } catch (e) {
        console.error('RainCurtain.ws.getLocalIPs error:', e);
        return { ipv4: '127.0.0.1', ipv6: null };
      }
    },

    getInstances: async function() {
      try {
        return await _call('rc_ws_get_instances', {});
      } catch (e) {
        console.error('RainCurtain.ws.getInstances error:', e);
        return [];
      }
    },

    on: function(instanceId, event, callback) {
      if (!instanceId || !event || typeof callback !== 'function') return;
      if (!_listeners[instanceId]) _listeners[instanceId] = {};
      if (!_listeners[instanceId][event]) _listeners[instanceId][event] = [];
      _listeners[instanceId][event].push(callback);
      // 注册监听器后立即 flush 缓冲，将之前到达的事件投递出去
      _flushBuffer(instanceId);
    },

    off: function(instanceId, event, callback) {
      var cbs = _listeners[instanceId] && _listeners[instanceId][event];
      if (!cbs) return;
      if (callback) {
        var idx = cbs.indexOf(callback);
        if (idx !== -1) cbs.splice(idx, 1);
      } else {
        // 未传 callback 则移除该事件所有监听
        delete _listeners[instanceId][event];
      }
    }
  };
})();
""";

  /// 初始化 WebSocket 管理器
  /// [getWebViewController] 用于在事件推送时获取当前 WebView 控制器
  /// [isMounted] 用于检查 State 是否仍然 mounted
  void initWsManager(InAppWebViewController? Function() getWebViewController, bool Function() isMounted) {
    wsManager = WsManager(onEvent: (instanceId, event, payload) {
      _pushWsEvent(instanceId, event, payload, getWebViewController, isMounted);
    });
  }

  /// 推送 WebSocket 事件到 JS 侧
  void _pushWsEvent(
    String instanceId,
    String event,
    Map<String, dynamic> payload,
    InAppWebViewController? Function() getWebViewController,
    bool Function() isMounted,
  ) {
    final controller = getWebViewController();
    if (controller == null || !isMounted()) return;
    final payloadJson = jsonEncode(payload);
    // 使用 JSON.parse 避免字符串中特殊字符问题
    controller
        .evaluateJavascript(
          source:
              'if(window.__rc_ws_event) window.__rc_ws_event("$instanceId", "$event", JSON.parse(${jsonEncode(payloadJson)}));',
        )
        .catchError(
          (e) => debugPrint('[RC WS] evaluateJavascript error: $e'),
        );
  }

  /// 注册 WebSocket Handler
  void registerWsHandlers(InAppWebViewController controller) {
    // 创建 WebSocket 服务端
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_create_server',
      callback: (args) async {
        try {
          final data = args.isNotEmpty ? args[0] as Map<dynamic, dynamic> : {};
          final port = (data['port'] as num?)?.toInt() ?? 0;
          final host = data['host'] as String? ?? '::';
          final useTLS = data['tls'] as bool? ?? false;
          return await wsManager.createServer(port: port, host: host, useTLS: useTLS);
        } catch (e) {
          debugPrint('rc_ws_create_server error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 连接远程 WebSocket 服务端
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_connect',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final url = data['url'] as String?;
          if (url == null || url.isEmpty) {
            return {'error': 'Missing url'};
          }
          return await wsManager.connect(url: url);
        } catch (e) {
          debugPrint('rc_ws_connect error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 发送文本消息
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_send',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final clientId = data['clientId'] as String?;
          final message = data['data'] as String?;
          if (instanceId == null || message == null) {
            return {'error': 'Missing instanceId or data'};
          }
          return wsManager.send(instanceId, clientId, message);
        } catch (e) {
          debugPrint('rc_ws_send error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 发送二进制消息
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_send_binary',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final clientId = data['clientId'] as String?;
          final b64Data = data['data'] as String?;
          if (instanceId == null || b64Data == null) {
            return {'error': 'Missing instanceId or data'};
          }
          final bytes = base64Decode(b64Data);
          return wsManager.sendBinary(
              instanceId, clientId, Uint8List.fromList(bytes));
        } catch (e) {
          debugPrint('rc_ws_send_binary error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 广播文本消息
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_broadcast',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final message = data['data'] as String?;
          if (instanceId == null || message == null) {
            return {'error': 'Missing instanceId or data'};
          }
          return wsManager.broadcast(instanceId, message);
        } catch (e) {
          debugPrint('rc_ws_broadcast error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 广播二进制消息
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_broadcast_binary',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final b64Data = data['data'] as String?;
          if (instanceId == null || b64Data == null) {
            return {'error': 'Missing instanceId or data'};
          }
          final bytes = base64Decode(b64Data);
          return wsManager.broadcastBinary(
              instanceId, Uint8List.fromList(bytes));
        } catch (e) {
          debugPrint('rc_ws_broadcast_binary error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 断开指定客户端
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_disconnect_client',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final clientId = data['clientId'] as String?;
          final code = (data['code'] as num?)?.toInt();
          final reason = data['reason'] as String?;
          if (instanceId == null || clientId == null) {
            return {'error': 'Missing instanceId or clientId'};
          }
          return await wsManager.disconnectClient(
              instanceId, clientId, code, reason);
        } catch (e) {
          debugPrint('rc_ws_disconnect_client error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 关闭服务端实例
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_close_server',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          if (instanceId == null) {
            return {'error': 'Missing instanceId'};
          }
          return await wsManager.closeServer(instanceId);
        } catch (e) {
          debugPrint('rc_ws_close_server error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 关闭客户端连接
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_close_client',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final code = (data['code'] as num?)?.toInt();
          final reason = data['reason'] as String?;
          if (instanceId == null) {
            return {'error': 'Missing instanceId'};
          }
          return await wsManager.closeClient(instanceId, code, reason);
        } catch (e) {
          debugPrint('rc_ws_close_client error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 获取已连接客户端列表
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_get_clients',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          if (instanceId == null) {
            return {'error': 'Missing instanceId'};
          }
          return wsManager.getClients(instanceId);
        } catch (e) {
          debugPrint('rc_ws_get_clients error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 获取本机局域网 IP
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_get_local_ip',
      callback: (args) async {
        try {
          return await WsManager.getLocalIP();
        } catch (e) {
          debugPrint('rc_ws_get_local_ip error: $e');
          return '127.0.0.1';
        }
      },
    );

    // 获取本机局域网 IPv6 地址
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_get_local_ipv6',
      callback: (args) async {
        try {
          return await WsManager.getLocalIPv6();
        } catch (e) {
          debugPrint('rc_ws_get_local_ipv6 error: $e');
          return null;
        }
      },
    );

    // 获取所有局域网 IP（IPv4 + IPv6）
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_get_local_ips',
      callback: (args) async {
        try {
          return await WsManager.getLocalIPs();
        } catch (e) {
          debugPrint('rc_ws_get_local_ips error: $e');
          return {'ipv4': '127.0.0.1', 'ipv6': null};
        }
      },
    );

    // 获取所有活跃 WS 实例
    controller.addJavaScriptHandler(
      handlerName: 'rc_ws_get_instances',
      callback: (args) async {
        try {
          return wsManager.getInstances();
        } catch (e) {
          debugPrint('rc_ws_get_instances error: $e');
          return [];
        }
      },
    );
  }

  /// 释放 WebSocket 资源
  void disposeWs() {
    wsManager.disposeAll();
  }
}
