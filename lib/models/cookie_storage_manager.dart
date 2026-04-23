import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

/// Cookie 存储管理器
/// 负责管理插件的 Cookie 数据持久化
class CookieStorageManager {
  final Directory storageDir;
  final CookieManager cookieManager = CookieManager.instance();

  CookieStorageManager({required this.storageDir});

  /// 获取插件的 Cookie 文件路径
  String _getCookieFilePath(String pluginId) {
    return p.join(storageDir.path, '${pluginId}_cookies.json');
  }

  /// 保存插件的 Cookie
  Future<void> saveCookiesForPlugin(String pluginId, WebUri url) async {
    try {
      final cookies = await cookieManager.getCookies(url: url);
      
      if (cookies.isEmpty) {
        debugPrint('No cookies to save for plugin: $pluginId');
        return;
      }

      final cookieList = cookies.map((cookie) => {
        'name': cookie.name,
        'value': cookie.value,
        'domain': cookie.domain,
        'path': cookie.path,
        'expiresDate': cookie.expiresDate,
        'isSecure': cookie.isSecure,
        'isHttpOnly': cookie.isHttpOnly,
        'sameSite': cookie.sameSite?.toNativeValue(),
      }).toList();

      final file = File(_getCookieFilePath(pluginId));
      final jsonData = {
        'cookies': cookieList,
        'url': url.toString(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await file.writeAsString(
        jsonEncode(jsonData),
        flush: true,
      );
      
      debugPrint('Saved ${cookies.length} cookies for plugin: $pluginId');
    } catch (e) {
      debugPrint('Failed to save cookies for $pluginId: $e');
    }
  }

  /// 加载插件的 Cookie
  Future<void> loadCookiesForPlugin(String pluginId, WebUri url) async {
    try {
      final file = File(_getCookieFilePath(pluginId));
      if (!await file.exists()) {
        debugPrint('No saved cookies for plugin: $pluginId');
        return;
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      final cookieList = jsonData['cookies'] as List<dynamic>;

      for (final cookieData in cookieList) {
        final data = cookieData as Map<String, dynamic>;
        
        await cookieManager.setCookie(
          url: url,
          name: data['name'] as String,
          value: data['value'] as String,
          domain: data['domain'] as String?,
          path: data['path'] as String? ?? '/',
          expiresDate: data['expiresDate'] as int?,
          isSecure: data['isSecure'] as bool? ?? false,
          isHttpOnly: data['isHttpOnly'] as bool? ?? false,
          sameSite: data['sameSite'] != null
              ? HTTPCookieSameSitePolicy.fromNativeValue(data['sameSite'].toString())
              : null,
        );
      }

      debugPrint('Loaded ${cookieList.length} cookies for plugin: $pluginId');
    } catch (e) {
      debugPrint('Failed to load cookies for $pluginId: $e');
    }
  }

  /// 获取插件的所有 Cookie（从文件读取）
  Future<List<Map<String, dynamic>>> getCookiesForPlugin(String pluginId) async {
    try {
      final file = File(_getCookieFilePath(pluginId));
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      final cookieList = jsonData['cookies'] as List<dynamic>;

      return cookieList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      debugPrint('Failed to get cookies for $pluginId: $e');
      return [];
    }
  }

  /// 清除插件的 Cookie
  Future<void> clearCookiesForPlugin(String pluginId) async {
    try {
      final file = File(_getCookieFilePath(pluginId));
      if (await file.exists()) {
        await file.delete();
        debugPrint('Cookies cleared for plugin: $pluginId');
      }
    } catch (e) {
      debugPrint('Failed to clear cookies for $pluginId: $e');
    }
  }

  /// 计算 Cookie 数据大小（字节）
  Future<int> getCookiesSizeForPlugin(String pluginId) async {
    try {
      final file = File(_getCookieFilePath(pluginId));
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      debugPrint('Failed to get cookies size for $pluginId: $e');
      return 0;
    }
  }

  /// 获取 Cookie 数量
  Future<int> getCookieCountForPlugin(String pluginId) async {
    try {
      final cookies = await getCookiesForPlugin(pluginId);
      return cookies.length;
    } catch (e) {
      debugPrint('Failed to get cookie count for $pluginId: $e');
      return 0;
    }
  }

  /// 获取所有插件的 Cookie 文件列表
  Future<List<String>> getAllPluginIds() async {
    try {
      if (!await storageDir.exists()) {
        return [];
      }

      final files = await storageDir.list().toList();
      final pluginIds = <String>[];

      for (final file in files) {
        if (file is File && file.path.endsWith('_cookies.json')) {
          final filename = p.basename(file.path);
          final pluginId = filename.replaceAll('_cookies.json', '');
          pluginIds.add(pluginId);
        }
      }

      return pluginIds;
    } catch (e) {
      debugPrint('Failed to get all plugin IDs: $e');
      return [];
    }
  }
}
