import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../models/dns_manager.dart';

/// DNS 相关的 JS polyfill 和 Handler 注册
mixin DnsMixin {
  late final DnsManager dnsManager;

  /// DNS API polyfill — 注入 window.RainCurtain.dns
  static const String polyfillJS = r"""
(function() {
  if (window.__rc_dns_patched) return;
  window.__rc_dns_patched = true;

  function _call(handler, args) {
    if (!window.flutter_inappwebview) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(handler, args);
  }

  // 确保 RainCurtain 对象存在
  if (!window.RainCurtain) window.RainCurtain = {};

  window.RainCurtain.dns = {
    resolve: async function(domain, options) {
      try {
        options = options || {};
        return await _call('rc_dns_resolve', {
          domain: domain,
          type: options.type || 'A',
          server: options.server || null,
          port: options.port || 53,
          timeout: options.timeout || 5000
        });
      } catch (e) {
        return { error: e.message || String(e) };
      }
    },

    resolveAll: async function(queries, options) {
      try {
        if (!Array.isArray(queries) || queries.length === 0) {
          return { error: 'queries must be a non-empty array' };
        }
        options = options || {};
        return await _call('rc_dns_resolve_all', {
          queries: queries,
          server: options.server || null,
          port: options.port || 53,
          timeout: options.timeout || 5000,
          concurrency: options.concurrency || 5
        });
      } catch (e) {
        return { error: e.message || String(e) };
      }
    }
  };
})();
""";

  /// 初始化 DNS 管理器
  void initDnsManager() {
    dnsManager = DnsManager();
  }

  /// 注册 DNS Handler
  void registerDnsHandlers(InAppWebViewController controller) {
    // 单个域名 DNS 解析
    controller.addJavaScriptHandler(
      handlerName: 'rc_dns_resolve',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final domain = data['domain'] as String?;
          if (domain == null || domain.isEmpty) {
            return {'error': 'Missing domain'};
          }
          return await dnsManager.resolve(
            domain: domain,
            type: data['type'] as String? ?? 'A',
            server: data['server'] as String?,
            port: (data['port'] as num?)?.toInt() ?? 53,
            timeoutMs: (data['timeout'] as num?)?.toInt() ?? 5000,
          );
        } catch (e) {
          debugPrint('rc_dns_resolve error: $e');
          return {'error': e.toString()};
        }
      },
    );

    // 批量 DNS 解析
    controller.addJavaScriptHandler(
      handlerName: 'rc_dns_resolve_all',
      callback: (args) async {
        try {
          if (args.isEmpty) return {'error': 'Missing arguments'};
          final data = args[0] as Map<dynamic, dynamic>;
          final queriesRaw = data['queries'] as List?;
          if (queriesRaw == null || queriesRaw.isEmpty) {
            return {'error': 'queries must be a non-empty array'};
          }
          final queries = queriesRaw
              .map((q) => Map<String, dynamic>.from(q as Map))
              .toList();
          return await dnsManager.resolveAll(
            queries: queries,
            server: data['server'] as String?,
            port: (data['port'] as num?)?.toInt() ?? 53,
            timeoutMs: (data['timeout'] as num?)?.toInt() ?? 5000,
            concurrency: (data['concurrency'] as num?)?.toInt() ?? 5,
          );
        } catch (e) {
          debugPrint('rc_dns_resolve_all error: $e');
          return {'error': e.toString()};
        }
      },
    );
  }

  /// 释放 DNS 管理器资源
  void disposeDns() {
    dnsManager.dispose();
  }
}
