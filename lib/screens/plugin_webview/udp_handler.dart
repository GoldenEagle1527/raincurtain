import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/udp_manager.dart';

/// UDP 相关的 JS polyfill 和 Handler 注册
mixin UdpMixin {
  late final UdpManager udpManager;

  /// UDP API polyfill — 注入 window.RainCurtain.udp
  static const String polyfillJS = r"""
(function() {
  if (window.__rc_udp_patched) return;
  window.__rc_udp_patched = true;

  var _listeners = {}; // instanceId -> { event -> [cb] }
  var _buffer = {};    // instanceId -> [{event, payload}]  事件缓冲

  function _call(handler, args) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(handler, args);
  }

  // base64 → ArrayBuffer
  function _b64ToArrayBuffer(b64) {
    var raw = atob(b64);
    var arr = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) arr[i] = raw.charCodeAt(i);
    return arr.buffer;
  }

  // 分发单个事件到回调
  function _dispatch(instanceId, event, payload, cbs) {
    var list = cbs.slice();
    for (var i = 0; i < list.length; i++) {
      try {
        switch (event) {
          case 'message':
            // payload: { data (base64), text (string|null), address, port }
            // text 非 null 时传文本，否则传 ArrayBuffer
            if (payload.text !== null && payload.text !== undefined) {
              list[i](payload.text, payload.address, payload.port);
            } else {
              var buf = _b64ToArrayBuffer(payload.data);
              list[i](buf, payload.address, payload.port);
            }
            break;
          case 'error':
            list[i](payload.message);
            break;
          case 'close':
            list[i]();
            break;
          default:
            list[i](payload);
        }
      } catch (e) {
        console.error('[RainCurtain.udp] Event callback error:', event, e);
      }
    }
  }

  // Flutter 侧推送事件的入口
  window.__rc_udp_event = function(instanceId, event, payload) {
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

  window.RainCurtain.udp = {
    bind: async function(options) {
      try {
        return await _call('rc_udp_bind', options || {});
      } catch (e) {
        console.error('RainCurtain.udp.bind error:', e);
        return { error: e.message || String(e) };
      }
    },

    send: async function(instanceId, address, port, data) {
      try {
        return await _call('rc_udp_send', { instanceId: instanceId, address: address, port: port, data: data });
      } catch (e) {
        console.error('RainCurtain.udp.send error:', e);
        return { error: e.message || String(e) };
      }
    },

    sendBinary: async function(instanceId, address, port, arrayBuffer) {
      try {
        var bytes = new Uint8Array(arrayBuffer);
        var binary = '';
        for (var i = 0; i < bytes.length; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        var base64 = btoa(binary);
        return await _call('rc_udp_send_binary', { instanceId: instanceId, address: address, port: port, data: base64 });
      } catch (e) {
        console.error('RainCurtain.udp.sendBinary error:', e);
        return { error: e.message || String(e) };
      }
    },

    close: async function(instanceId) {
      try {
        delete _listeners[instanceId];
        delete _buffer[instanceId];
        return await _call('rc_udp_close', { instanceId: instanceId });
      } catch (e) {
        console.error('RainCurtain.udp.close error:', e);
        return { error: e.message || String(e) };
      }
    },

    setBroadcast: async function(instanceId, enabled) {
      try {
        return await _call('rc_udp_set_broadcast', { instanceId: instanceId, enabled: enabled });
      } catch (e) {
        console.error('RainCurtain.udp.setBroadcast error:', e);
        return { error: e.message || String(e) };
      }
    },

    joinMulticast: async function(instanceId, address) {
      try {
        return await _call('rc_udp_join_multicast', { instanceId: instanceId, address: address });
      } catch (e) {
        console.error('RainCurtain.udp.joinMulticast error:', e);
        return { error: e.message || String(e) };
      }
    },

    leaveMulticast: async function(instanceId, address) {
      try {
        return await _call('rc_udp_leave_multicast', { instanceId: instanceId, address: address });
      } catch (e) {
        console.error('RainCurtain.udp.leaveMulticast error:', e);
        return { error: e.message || String(e) };
      }
    },

    getInstances: async function() {
      try {
        return await _call('rc_udp_get_instances', {});
      } catch (e) {
        console.error('RainCurtain.udp.getInstances error:', e);
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

  /// 初始化 UDP 管理器
  /// [getWebViewController] 用于在事件推送时获取当前 WebView 控制器
  /// [isMounted] 用于检查 State 是否仍然 mounted
  void initUdpManager(InAppWebViewController? Function() getWebViewController, bool Function() isMounted) {
    udpManager = UdpManager(onEvent: (instanceId, event, payload) {
      _pushUdpEvent(instanceId, event, payload, getWebViewController, isMounted);
    });
  }

  /// 推送 UDP 事件到 JS 侧
  void _pushUdpEvent(
    String instanceId,
    String event,
    Map<String, dynamic> payload,
    InAppWebViewController? Function() getWebViewController,
    bool Function() isMounted,
  ) {
    final controller = getWebViewController();
    if (controller == null || !isMounted()) return;
    final payloadJson = jsonEncode(payload);
    // 使用 JSON.parse 避免字符串中特殊字符问题（与 WS 同模式）
    controller.evaluateJavascript(
      source:
          'if(window.__rc_udp_event) window.__rc_udp_event("$instanceId", "$event", JSON.parse(${jsonEncode(payloadJson)}));',
    );
  }

  /// 注册 UDP Handler
  void registerUdpHandlers(InAppWebViewController controller) {
    // 绑定 UDP socket
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_bind',
      callback: (args) async {
        try {
          final data = args.isNotEmpty ? args[0] as Map<dynamic, dynamic> : {};
          final port = (data['port'] as num?)?.toInt() ?? 0;
          final host = data['host'] as String? ?? '0.0.0.0';
          final broadcast = data['broadcast'] as bool? ?? false;
          return await udpManager.bind(port: port, host: host, broadcast: broadcast);
        } catch (e) {
          debugPrint('rc_udp_bind error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 发送文本数据报
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_send',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final address = data['address'] as String?;
          final port = (data['port'] as num?)?.toInt();
          final message = data['data'] as String?;
          if (instanceId == null || address == null || port == null || message == null) {
            return {'error': 'Missing instanceId, address, port or data'};
          }
          return udpManager.send(instanceId, address, port, message);
        } catch (e) {
          debugPrint('rc_udp_send error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 发送二进制数据报
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_send_binary',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final address = data['address'] as String?;
          final port = (data['port'] as num?)?.toInt();
          final b64Data = data['data'] as String?;
          if (instanceId == null || address == null || port == null || b64Data == null) {
            return {'error': 'Missing instanceId, address, port or data'};
          }
          final bytes = base64Decode(b64Data);
          return udpManager.sendBinary(instanceId, address, port, Uint8List.fromList(bytes));
        } catch (e) {
          debugPrint('rc_udp_send_binary error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 关闭 UDP socket
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_close',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          if (instanceId == null) {
            return {'error': 'Missing instanceId'};
          }
          return await udpManager.close(instanceId);
        } catch (e) {
          debugPrint('rc_udp_close error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 设置广播开关
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_set_broadcast',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final enabled = data['enabled'] as bool?;
          if (instanceId == null || enabled == null) {
            return {'error': 'Missing instanceId or enabled'};
          }
          return udpManager.setBroadcast(instanceId, enabled);
        } catch (e) {
          debugPrint('rc_udp_set_broadcast error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 加入组播组
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_join_multicast',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final address = data['address'] as String?;
          if (instanceId == null || address == null) {
            return {'error': 'Missing instanceId or address'};
          }
          return udpManager.joinMulticast(instanceId, address);
        } catch (e) {
          debugPrint('rc_udp_join_multicast error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 离开组播组
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_leave_multicast',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final instanceId = data['instanceId'] as String?;
          final address = data['address'] as String?;
          if (instanceId == null || address == null) {
            return {'error': 'Missing instanceId or address'};
          }
          return udpManager.leaveMulticast(instanceId, address);
        } catch (e) {
          debugPrint('rc_udp_leave_multicast error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 获取所有活跃 UDP 实例
    controller.addJavaScriptHandler(
      handlerName: 'rc_udp_get_instances',
      callback: (args) async {
        try {
          return udpManager.getInstances();
        } catch (e) {
          debugPrint('rc_udp_get_instances error: $e');
          return [];
        }
      },
    );
  }

  /// 释放 UDP 资源
  void disposeUdp() {
    udpManager.disposeAll();
  }
}
