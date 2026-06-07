import 'package:yaml/yaml.dart';

/// 从插件市场 API 返回的在线插件实体
class MarketPlugin {
  final String pluginId;
  final String version;
  final String updatedAt;
  final String downloadUrl;
  final String manifestUrl;
  final String name;
  final String description;
  final String? icon;
  final List<String> tags;
  final String changelog;

  const MarketPlugin({
    required this.pluginId,
    required this.version,
    required this.updatedAt,
    required this.downloadUrl,
    required this.manifestUrl,
    required this.name,
    required this.description,
    this.icon,
    required this.tags,
    required this.changelog,
  });

  factory MarketPlugin.fromJson(Map<String, dynamic> json) {
    final tagsList = json['tags'];
    List<String> tagsDefs = [];
    if (tagsList != null && tagsList is List) {
      tagsDefs = tagsList.map((e) => e.toString()).toList();
    }
    return MarketPlugin(
      pluginId: (json['plugin_id'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? '').toString(),
      manifestUrl: (json['manifest_url'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      icon: json['icon']?.toString(),
      tags: tagsDefs,
      changelog: (json['changelog'] ?? '').toString(),
    );
  }
}

/// 从 manifest_url 拉取并解析得到的附加信息
class ManifestInfo {
  final String name;
  final String description;
  final String author;
  final String? icon;
  final List<String> tags;

  const ManifestInfo({
    required this.name,
    required this.description,
    required this.author,
    this.icon,
    required this.tags,
  });

  factory ManifestInfo.fromYaml(YamlMap yaml) {
    final tagsList = yaml['tags'];
    List<String> tagsDefs = [];
    if (tagsList != null && tagsList is List) {
      tagsDefs = tagsList.map((e) => e.toString()).toList();
    }
    return ManifestInfo(
      name: (yaml['name'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      author: (yaml['author'] ?? '').toString(),
      icon: yaml['icon']?.toString(),
      tags: tagsDefs,
    );
  }
}
