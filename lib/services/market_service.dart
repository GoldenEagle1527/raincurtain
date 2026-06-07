import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/market_plugin.dart';
import '../models/plugin_manager.dart';

class MarketService {
  static const String apiBaseUrl =
      'https://api.raincurtain-pluginmarket.goldeneaglepersonal.de5.net';

  /// 获取在线插件列表
  static Future<List<MarketPlugin>> fetchMarketPlugins([String query = '']) async {
    final url = query.isNotEmpty
        ? '$apiBaseUrl/api/plugins?q=${Uri.encodeComponent(query)}'
        : '$apiBaseUrl/api/plugins';
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final jsonMap = json.decode(res.body);
      if (jsonMap['success'] == true) {
        final list = jsonMap['data'] as List;
        return list.map((x) => MarketPlugin.fromJson(x)).toList();
      } else {
        throw Exception(jsonMap['error'] ?? '拉取列表失败');
      }
    } else {
      throw Exception('HTTP 服务端响应异常 (${res.statusCode})');
    }
  }

  /// 拉取某插件全部历史版本
  static Future<List<MarketPlugin>> fetchPluginVersions(String pluginId) async {
    final url = '$apiBaseUrl/api/plugins/${Uri.encodeComponent(pluginId)}';
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final jsonMap = json.decode(res.body);
      if (jsonMap['success'] == true) {
        final list = (jsonMap['data'] as List)
            .map((x) => MarketPlugin.fromJson(x))
            .toList();
        return list;
      } else {
        throw Exception(jsonMap['error'] ?? '拉取历史版本失败');
      }
    } else {
      throw Exception('HTTP 服务端响应异常 (${res.statusCode})');
    }
  }

  /// 下载并安装插件
  static Future<void> downloadAndInstall({
    required MarketPlugin plugin,
    required PluginManager pluginManager,
    required void Function(double progress) onProgress,
  }) async {
    final cdnUrl = plugin.downloadUrl;
    final directUrl =
        '$apiBaseUrl/api/plugins/download/${Uri.encodeComponent(plugin.pluginId)}/${Uri.encodeComponent(plugin.version)}?direct=true';

    debugPrint('[Market] 准备下载插件: "${plugin.pluginId}" v${plugin.version}');
    debugPrint('[Market] 优先尝试 CDN 下载 URL: $cdnUrl');

    var client = http.Client();
    var request = http.Request('GET', Uri.parse(cdnUrl));
    var response = await client.send(request);

    if (response.statusCode != 200) {
      debugPrint('[Market] CDN 下载失败，状态码: ${response.statusCode}');
      debugPrint('[Market] 正在尝试 Worker 直连下载通道: $directUrl');

      client = http.Client();
      request = http.Request('GET', Uri.parse(directUrl));
      response = await client.send(request);

      if (response.statusCode != 200) {
        debugPrint('[Market] 直连下载也失败，状态码: ${response.statusCode}');
        throw Exception('下载请求均告失败 (状态码: ${response.statusCode})');
      } else {
        debugPrint('[Market] 直连通道连接成功，开始流式传输数据...');
      }
    } else {
      debugPrint('[Market] CDN 连接成功，开始流式传输数据...');
    }

    final contentLength = response.contentLength ?? 0;
    List<int> bytes = [];
    int downloaded = 0;

    await for (var chunk in response.stream) {
      bytes.addAll(chunk);
      downloaded += chunk.length;
      if (contentLength > 0) {
        onProgress(downloaded / contentLength);
      }
    }

    // 保存至临时文件
    final tempDir = await getTemporaryDirectory();
    final tempFile =
        File(p.join(tempDir.path, '${plugin.pluginId}-${plugin.version}.rcplugin'));
    await tempFile.writeAsBytes(bytes);

    // 调用本地一键解压并注册
    await pluginManager.installPluginFromRcPlugin(tempFile, overwrite: true);

    // 清理临时包
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }
}
