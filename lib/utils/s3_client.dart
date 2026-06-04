import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// 免签公共 HTTP 客户端（用于代替原需要签名的 S3Client）
/// 直接从公开的 R2/S3 托管地址获取 update.json 和更新包，不包含任何敏感凭证。
class S3Client {
  final String publicUrl;

  S3Client({
    required this.publicUrl,
  });

  /// 读取公开托管地址中指定对象的文本内容
  Future<String> readObject(String objectKey) async {
    final cleanBaseUrl = publicUrl.replaceAll(RegExp(r'/$'), '');
    final encodedKey = objectKey.split('/').map(Uri.encodeComponent).join('/');
    final requestUri = Uri.parse('$cleanBaseUrl/$encodedKey');

    final response = await http.get(requestUri);
    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    } else {
      throw Exception('读取文件失败，状态码: ${response.statusCode}, 响应: ${response.body}');
    }
  }

  /// 下载公开托管地址中指定文件到本地，支持下载进度回调
  Future<void> downloadObject(
    String objectKey,
    String savePath, {
    void Function(double progress)? onProgress,
  }) async {
    final cleanBaseUrl = publicUrl.replaceAll(RegExp(r'/$'), '');
    final encodedKey = objectKey.split('/').map(Uri.encodeComponent).join('/');
    final requestUri = Uri.parse('$cleanBaseUrl/$encodedKey');

    final request = http.Request('GET', requestUri);
    final response = await request.send();

    if (response.statusCode != 200) {
      throw Exception('下载文件失败，状态码: ${response.statusCode}');
    }

    // 确保父目录存在
    final file = File(savePath);
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final sink = file.openWrite();
    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;

    try {
      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            onProgress(receivedBytes / totalBytes);
          }
        },
        onError: (err) {
          throw err;
        },
        cancelOnError: true,
      ).asFuture();
    } finally {
      await sink.close();
    }
  }
}
