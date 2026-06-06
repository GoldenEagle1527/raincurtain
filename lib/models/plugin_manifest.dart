import 'plugin_icon.dart';
import 'io_definition.dart';

enum VersionComparisonResult {
  newer,
  older,
  same,
}

/// 存储列定义
class StorageColumnDefinition {
  final String name;
  final String type; // text, integer, real, boolean

  static const List<String> supportedTypes = ['text', 'integer', 'real', 'boolean'];
  static final RegExp _nameRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  const StorageColumnDefinition({
    required this.name,
    required this.type,
  });

  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('storage column name 不能为空');
    }
    if (!_nameRegex.hasMatch(name)) {
      throw FormatException(
          'storage column name "$name" 格式无效，必须以字母或下划线开头，后续为字母、数字、下划线');
    }
    if (name == '_id') {
      throw const FormatException('storage column name 不能为 "_id"，该名称为系统保留主键');
    }
    if (!supportedTypes.contains(type)) {
      throw FormatException(
          'storage column type "$type" 无效，支持: ${supportedTypes.join(', ')}');
    }
  }

  /// SQLite 列类型
  String get sqliteType => switch (type) {
    'text' => 'TEXT',
    'integer' => 'INTEGER',
    'real' => 'REAL',
    'boolean' => 'INTEGER', // boolean 存为 0/1
    _ => 'TEXT',
  };

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
  };

  factory StorageColumnDefinition.fromJson(Map<String, dynamic> json) {
    return StorageColumnDefinition(
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }

  factory StorageColumnDefinition.fromYaml(dynamic yaml) {
    if (yaml is! Map) {
      throw const FormatException('storage column 定义必须是对象');
    }
    return StorageColumnDefinition.fromJson(Map<String, dynamic>.from(yaml));
  }
}

/// 存储表定义
class StorageTableDefinition {
  final String name;
  final List<StorageColumnDefinition> columns;

  static final RegExp _nameRegex = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  const StorageTableDefinition({
    required this.name,
    required this.columns,
  });

  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('storage table name 不能为空');
    }
    if (!_nameRegex.hasMatch(name)) {
      throw FormatException(
          'storage table name "$name" 格式无效，必须以字母或下划线开头，后续为字母、数字、下划线');
    }
    if (columns.isEmpty) {
      throw FormatException('storage table "$name" 至少需要定义一个列');
    }

    final columnNames = <String>{};
    for (final col in columns) {
      col.validate();
      if (columnNames.contains(col.name)) {
        throw FormatException('storage table "$name" 中存在重复列名: ${col.name}');
      }
      columnNames.add(col.name);
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'columns': columns.map((c) => c.toJson()).toList(),
  };

  factory StorageTableDefinition.fromJson(Map<String, dynamic> json) {
    final columnsList = json['columns'];
    if (columnsList == null || columnsList is! List) {
      throw const FormatException('storage table 缺少 columns 列表');
    }
    return StorageTableDefinition(
      name: (json['name'] ?? '').toString(),
      columns: columnsList
          .map((c) => StorageColumnDefinition.fromJson(
              Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }

  factory StorageTableDefinition.fromYaml(dynamic yaml) {
    if (yaml is! Map) {
      throw const FormatException('storage table 定义必须是对象');
    }
    final map = Map<String, dynamic>.from(yaml);
    final columnsList = map['columns'];
    if (columnsList == null || columnsList is! List) {
      throw const FormatException('storage table 缺少 columns 列表');
    }
    return StorageTableDefinition(
      name: (map['name'] ?? '').toString(),
      columns: columnsList
          .map((c) => StorageColumnDefinition.fromYaml(c))
          .toList(),
    );
  }
}

class PluginManifest {
  PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.tags = const [],
    this.icon = const DefaultIcon(),
    this.inputs = const [],
    this.outputs = const [],
    this.storage = const [],
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final List<String> tags;
  final PluginIcon icon;
  final List<IODefinition> inputs;
  final List<IODefinition> outputs;
  final List<StorageTableDefinition> storage;

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

    // 验证存储定义
    final tableNames = <String>{};
    for (final table in storage) {
      table.validate();
      if (tableNames.contains(table.name)) {
        throw FormatException('Duplicate storage table name: ${table.name}');
      }
      tableNames.add(table.name);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'tags': tags,
    'icon': _iconToString(icon),
    'inputs': inputs.map((e) => e.toJson()).toList(),
    'outputs': outputs.map((e) => e.toJson()).toList(),
    'storage': storage.map((e) => e.toJson()).toList(),
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

    // storage 是可选字段，默认空列表
    final storageList = json['storage'];
    List<StorageTableDefinition> storageDefs = [];
    if (storageList != null) {
      if (storageList is! List) {
        throw const FormatException('manifest.yml 的 storage 必须是列表');
      }
      storageDefs = storageList
          .map((e) => StorageTableDefinition.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    final tagsList = json['tags'];
    List<String> tagsDefs = [];
    if (tagsList != null && tagsList is List) {
      tagsDefs = tagsList.map((e) => e.toString()).toList();
    }

    final manifest = PluginManifest(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      author: (json['author'] ?? '').toString(),
      tags: tagsDefs,
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
      storage: storageDefs,
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

    // storage 是可选字段，默认空列表
    final storageList = yaml['storage'];
    List<StorageTableDefinition> storageDefs = [];
    if (storageList != null) {
      if (storageList is! List) {
        throw const FormatException('manifest.yml 的 storage 必须是列表');
      }
      storageDefs = storageList
          .map((e) => StorageTableDefinition.fromYaml(e))
          .toList();
    }

    final tagsList = yaml['tags'];
    List<String> tagsDefs = [];
    if (tagsList != null && tagsList is List) {
      tagsDefs = tagsList.map((e) => e.toString()).toList();
    }

    final manifest = PluginManifest(
      id: (yaml['id'] ?? '').toString(),
      name: (yaml['name'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      version: (yaml['version'] ?? '').toString(),
      author: (yaml['author'] ?? '').toString(),
      tags: tagsDefs,
      icon: PluginIcon.parse(yaml['icon']?.toString()),
      inputs: inputsList
          .map((e) => IODefinition.fromYaml(e, isInput: true))
          .toList(),
      outputs: outputsList
          .map((e) => IODefinition.fromYaml(e, isInput: false))
          .toList(),
      storage: storageDefs,
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
