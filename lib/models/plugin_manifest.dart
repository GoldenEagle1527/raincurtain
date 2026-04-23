import 'plugin_icon.dart';

enum VersionComparisonResult {
  newer,
  older,
  same,
}

class PluginManifest {
  PluginManifest({
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.icon = const DefaultIcon(),
  });

  final String name;
  final String description;
  final String version;
  final String author;
  final PluginIcon icon;

  static final RegExp _semverRegex = RegExp(r'^\d+\.\d+\.\d+$');

  static bool isValidVersion(String value) => _semverRegex.hasMatch(value.trim());

  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('manifest.yml 缺少有效的 name');
    }
    if (description.trim().isEmpty) {
      throw const FormatException('manifest.yml 缺少有效的 description');
    }
    if (author.trim().isEmpty) {
      throw const FormatException('manifest.yml 缺少有效的 author');
    }
    if (!isValidVersion(version)) {
      throw const FormatException('manifest.yml 中的 version 必须为语义化版本格式 X.Y.Z');
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'icon': _iconToString(icon),
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final manifest = PluginManifest(
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      icon: PluginIcon.parse(json['icon']?.toString()),
    );
    manifest.validate();
    return manifest;
  }

  factory PluginManifest.fromYamlMap(Map<dynamic, dynamic> yaml) {
    final manifest = PluginManifest(
      name: (yaml['name'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      version: (yaml['version'] ?? '').toString(),
      author: (yaml['author'] ?? '').toString(),
      icon: PluginIcon.parse(yaml['icon']?.toString()),
    );
    manifest.validate();
    return manifest;
  }

  static String? _iconToString(PluginIcon icon) {
    return switch (icon) {
      DefaultIcon() => null,
      MaterialIcon(:final iconName, :final variant) =>
        variant == MaterialIconVariant.filled
            ? 'material:$iconName'
            : 'material:$iconName:${_variantToString(variant)}',
      PluginImageIcon(:final relativePath) => relativePath,
    };
  }

  static String _variantToString(MaterialIconVariant variant) {
    return switch (variant) {
      MaterialIconVariant.filled => 'filled',
      MaterialIconVariant.outlined => 'outlined',
      MaterialIconVariant.rounded => 'rounded',
      MaterialIconVariant.sharp => 'sharp',
      MaterialIconVariant.twoTone => 'two-tone',
    };
  }

  VersionComparisonResult compareVersion(String otherVersion) {
    final currentParts = _parseVersion(version);
    final otherParts = _parseVersion(otherVersion);

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < otherParts[i]) {
        return VersionComparisonResult.older;
      } else if (currentParts[i] > otherParts[i]) {
        return VersionComparisonResult.newer;
      }
    }

    return VersionComparisonResult.same;
  }

  List<int> _parseVersion(String versionString) {
    final parts = versionString.trim().split('.');
    final result = <int>[];

    for (int i = 0; i < 3; i++) {
      if (i < parts.length) {
        result.add(int.tryParse(parts[i]) ?? 0);
      } else {
        result.add(0);
      }
    }

    return result;
  }
}
