import 'plugin_icon.dart';
import 'io_definition.dart';

enum VersionComparisonResult {
  newer,
  older,
  same,
}

class PluginManifest {
  PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.icon = const DefaultIcon(),
    this.inputs = const [],
    this.outputs = const [],
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final PluginIcon icon;
  final List<IODefinition> inputs;
  final List<IODefinition> outputs;

  static final RegExp _semverRegex = RegExp(r'^\d+\.\d+\.\d+$');
  static final RegExp _uuidV7Regex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-7[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static bool isValidVersion(String value) => _semverRegex.hasMatch(value.trim());
  static bool isValidId(String value) => _uuidV7Regex.hasMatch(value.trim());

  void validate() {
    if (!isValidId(id)) {
      throw const FormatException('manifest.yml 中的 id 必须为 UUID v7');
    }
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

    // 验证输入输出定义
    final inputNames = <String>{};
    for (final input in inputs) {
      input.validate();
      if (inputNames.contains(input.name)) {
        throw FormatException('Duplicate input name: ${input.name}');
      }
      inputNames.add(input.name);
    }

    final outputNames = <String>{};
    for (final output in outputs) {
      output.validate();
      if (outputNames.contains(output.name)) {
        throw FormatException('Duplicate output name: ${output.name}');
      }
      outputNames.add(output.name);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'icon': _iconToString(icon),
    'inputs': inputs.map((e) => e.toJson()).toList(),
    'outputs': outputs.map((e) => e.toJson()).toList(),
  };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final inputsList = json['inputs'];
    final outputsList = json['outputs'];

    // inputs 和 outputs 必须存在（可以是空列表）
    if (inputsList == null) {
      throw const FormatException('manifest.yml 缺少 inputs 字段（可以是空列表 []）');
    }
    if (outputsList == null) {
      throw const FormatException('manifest.yml 缺少 outputs 字段（可以是空列表 []）');
    }
    if (inputsList is! List) {
      throw const FormatException('manifest.yml 的 inputs 必须是列表');
    }
    if (outputsList is! List) {
      throw const FormatException('manifest.yml 的 outputs 必须是列表');
    }

    final manifest = PluginManifest(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      icon: PluginIcon.parse(json['icon']?.toString()),
      inputs: inputsList
          .map((e) => IODefinition.fromJson(
              Map<String, dynamic>.from(e as Map),
              isInput: true))
          .toList(),
      outputs: outputsList
          .map((e) => IODefinition.fromJson(
              Map<String, dynamic>.from(e as Map),
              isInput: false))
          .toList(),
    );
    manifest.validate();
    return manifest;
  }

  factory PluginManifest.fromYamlMap(Map<dynamic, dynamic> yaml) {
    final inputsList = yaml['inputs'];
    final outputsList = yaml['outputs'];

    // inputs 和 outputs 必须存在（可以是空列表）
    if (inputsList == null) {
      throw const FormatException('manifest.yml 缺少 inputs 字段（可以是空列表 []）');
    }
    if (outputsList == null) {
      throw const FormatException('manifest.yml 缺少 outputs 字段（可以是空列表 []）');
    }
    if (inputsList is! List) {
      throw const FormatException('manifest.yml 的 inputs 必须是列表');
    }
    if (outputsList is! List) {
      throw const FormatException('manifest.yml 的 outputs 必须是列表');
    }

    final manifest = PluginManifest(
      id: (yaml['id'] ?? '').toString(),
      name: (yaml['name'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      version: (yaml['version'] ?? '').toString(),
      author: (yaml['author'] ?? '').toString(),
      icon: PluginIcon.parse(yaml['icon']?.toString()),
      inputs: inputsList
          .map((e) => IODefinition.fromYaml(e, isInput: true))
          .toList(),
      outputs: outputsList
          .map((e) => IODefinition.fromYaml(e, isInput: false))
          .toList(),
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
