import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 网络请求性能指标
class FetchMetrics {
  final DateTime startTime;
  final String url;
  final String method;
  int? statusCode;
  int? responseSize;
  String? error;

  FetchMetrics({
    required this.url,
    required this.method,
  }) : startTime = DateTime.now();

  Duration get duration => DateTime.now().difference(startTime);

  void complete(int status, int size) {
    statusCode = status;
    responseSize = size;
  }

  void fail(String err) {
    error = err;
  }

  void log() {
    if (error != null) {
      debugPrint('[RainCurtain Fetch] \u274c $method $url\n  Error: $error\n  Duration: ${duration.inMilliseconds}ms');
    } else {
      debugPrint('[RainCurtain Fetch] \u2705 $method $url\n  Status: $statusCode\n  Size: ${responseSize ?? 0} bytes\n  Duration: ${duration.inMilliseconds}ms');
    }
  }
}

/// HTTP 响应缓存条目
class CachedResponse {
  final int statusCode;
  final String? reasonPhrase;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final DateTime cachedAt;
  final Duration maxAge;

  CachedResponse({
    required this.statusCode,
    required this.reasonPhrase,
    required this.headers,
    required this.bodyBytes,
    required this.maxAge,
  }) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > maxAge;

  /// 从响应头解析 max-age，默认 60 秒
  static Duration _parseMaxAge(Map<String, String> headers) {
    final cc = headers['cache-control'] ?? headers['Cache-Control'] ?? '';
    final match = RegExp(r'max-age=(\d+)').firstMatch(cc);
    if (match != null) {
      final seconds = int.tryParse(match.group(1) ?? '');
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds);
      }
    }
    // no-store / no-cache → don't cache
    if (cc.contains('no-store') || cc.contains('no-cache')) {
      return Duration.zero;
    }
    return const Duration(seconds: 60);
  }

  static CachedResponse? fromResponse(http.Response response) {
    final headers = response.headers;
    final maxAge = _parseMaxAge(headers);
    if (maxAge == Duration.zero) return null; // not cacheable
    return CachedResponse(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: headers,
      bodyBytes: response.bodyBytes,
      maxAge: maxAge,
    );
  }
}

/// LRU 请求缓存（仅缓存 GET 请求）
class RequestCache {
  static const int _maxEntries = 50;
  // LinkedHashMap preserves insertion order; we remove the oldest entry on overflow
  final LinkedHashMap<String, CachedResponse> _store =
      LinkedHashMap<String, CachedResponse>();

  CachedResponse? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    // Move to end (most-recently-used)
    _store.remove(key);
    _store[key] = entry;
    return entry;
  }

  void put(String key, CachedResponse entry) {
    _store.remove(key); // reset position
    if (_store.length >= _maxEntries) {
      _store.remove(_store.keys.first); // evict LRU
    }
    _store[key] = entry;
  }

  void clear() => _store.clear();
}
