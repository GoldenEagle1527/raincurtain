/// 类型 Schema 定义，用于描述 object 和 array 类型的内部结构
///
/// 支持基础 JSON Schema 子集：properties、required、type、description
/// 支持递归定义：object 属性可以是 object/array，array 元素可以是 object/array
sealed class TypeSchema {
  const TypeSchema();

  /// 最大递归深度限制
  static const int maxDepth = 5;

  Map<String, dynamic> toJson();
  void validate({int depth = 0});

  /// 从 JSON/YAML 解析 TypeSchema
  ///
  /// 对于简单类型（string, number, boolean），返回 null（无需额外 schema）。
  /// 对于 object 类型，解析 properties 和 required。
  /// 对于 array 类型，解析 items。
  static TypeSchema? fromJson(Map<String, dynamic> json, String type,
      {int depth = 0}) {
    if (depth > maxDepth) {
      throw FormatException('类型 Schema 嵌套深度超过上限 ($maxDepth)');
    }
    return switch (type) {
      'object' => ObjectTypeSchema._fromJson(json, depth: depth),
      'array' => ArrayTypeSchema._fromJson(json, depth: depth),
      _ => null, // 简单类型无需 schema
    };
  }

  /// 从包含 type 字段的 map 解析（用于 array items 和递归属性）
  static TypeSchema? fromTypedJson(Map<String, dynamic> json,
      {int depth = 0}) {
    final type = (json['type'] ?? '').toString();
    if (type.isEmpty) {
      throw const FormatException('类型 Schema 缺少 type 字段');
    }
    if (!IODefinition.supportedTypes.contains(type)) {
      throw FormatException('不支持的类型: $type');
    }
    return fromJson(json, type, depth: depth);
  }

  /// 生成人类可读的类型描述字符串
  String toDisplayString();
}

/// Object 类型 Schema - JSON Schema 基础子集
///
/// 支持 properties（属性名 → 属性定义）和 required（必需属性列表）
class ObjectTypeSchema extends TypeSchema {
  final Map<String, PropertySchema> properties;
  final List<String> required;

  const ObjectTypeSchema({
    required this.properties,
    this.required = const [],
  });

  @override
  void validate({int depth = 0}) {
    if (depth > TypeSchema.maxDepth) {
      throw FormatException('类型 Schema 嵌套深度超过上限 (${TypeSchema.maxDepth})');
    }

    // 验证 required 中的属性名必须在 properties 中存在
    for (final reqName in required) {
      if (!properties.containsKey(reqName)) {
        throw FormatException(
            'required 中的属性 "$reqName" 未在 properties 中定义');
      }
    }

    // 递归验证每个属性
    for (final entry in properties.entries) {
      entry.value.validate(depth: depth + 1);
    }
  }

  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'properties': properties
          .map((key, value) => MapEntry(key, value.toJson())),
    };
    if (required.isNotEmpty) {
      result['required'] = required;
    }
    return result;
  }

  factory ObjectTypeSchema._fromJson(Map<String, dynamic> json,
      {int depth = 0}) {
    final propsRaw = json['properties'];
    if (propsRaw == null) {
      // schema 字段本身可能就是包含 properties 的 map
      // 检查外层 json 中的 schema 字段
      final schemaRaw = json['schema'];
      if (schemaRaw is Map) {
        return ObjectTypeSchema._fromJson(
            Map<String, dynamic>.from(schemaRaw),
            depth: depth);
      }
      throw const FormatException('object 类型必须定义 schema.properties');
    }

    if (propsRaw is! Map) {
      throw const FormatException('schema.properties 必须是对象');
    }

    final properties = <String, PropertySchema>{};
    for (final entry in propsRaw.entries) {
      final propName = entry.key.toString();
      final propValue = entry.value;
      if (propValue is! Map) {
        throw FormatException('属性 "$propName" 的定义必须是对象');
      }
      properties[propName] =
          PropertySchema.fromJson(Map<String, dynamic>.from(propValue),
              depth: depth);
    }

    final requiredRaw = json['required'];
    final required = <String>[];
    if (requiredRaw is List) {
      for (final item in requiredRaw) {
        required.add(item.toString());
      }
    }

    return ObjectTypeSchema(properties: properties, required: required);
  }

  @override
  String toDisplayString() {
    if (properties.isEmpty) return 'object';
    final keys = properties.keys.take(3).join(', ');
    final suffix = properties.length > 3 ? ', ...' : '';
    return 'object{$keys$suffix}';
  }
}

/// Array 类型 Schema
///
/// 通过 items 字段定义元素类型，支持递归（元素为 object 时也有 schema）
class ArrayTypeSchema extends TypeSchema {
  final String itemType; // 元素的基础类型: string, number, boolean, object, array
  final TypeSchema? itemSchema; // 元素的详细 schema（仅 object/array 类型需要）

  const ArrayTypeSchema({
    required this.itemType,
    this.itemSchema,
  });

  @override
  void validate({int depth = 0}) {
    if (depth > TypeSchema.maxDepth) {
      throw FormatException('类型 Schema 嵌套深度超过上限 (${TypeSchema.maxDepth})');
    }
    if (!IODefinition.supportedTypes.contains(itemType)) {
      throw FormatException('array items 不支持的类型: $itemType');
    }
    if (itemType == 'object' && itemSchema == null) {
      throw const FormatException('array items 为 object 时必须定义 schema');
    }
    if (itemType == 'array' && itemSchema == null) {
      throw const FormatException('array items 为 array 时必须定义 items');
    }
    itemSchema?.validate(depth: depth + 1);
  }

  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'type': itemType};
    if (itemSchema != null) {
      if (itemSchema is ObjectTypeSchema) {
        result.addAll(itemSchema!.toJson());
      } else if (itemSchema is ArrayTypeSchema) {
        final arraySchema = itemSchema as ArrayTypeSchema;
        result['items'] = arraySchema.toJson();
      }
    }
    return result;
  }

  factory ArrayTypeSchema._fromJson(Map<String, dynamic> json,
      {int depth = 0}) {
    // items 可以在 json 本身的 'items' 字段中
    final itemsRaw = json['items'];
    if (itemsRaw == null) {
      throw const FormatException('array 类型必须定义 items');
    }

    if (itemsRaw is! Map) {
      throw const FormatException('array items 必须是对象');
    }

    final itemsMap = Map<String, dynamic>.from(itemsRaw);
    final itemType = (itemsMap['type'] ?? '').toString();

    if (itemType.isEmpty) {
      throw const FormatException('array items 缺少 type 字段');
    }
    if (!IODefinition.supportedTypes.contains(itemType)) {
      throw FormatException('array items 不支持的类型: $itemType');
    }

    TypeSchema? itemSchema;
    if (itemType == 'object') {
      itemSchema = ObjectTypeSchema._fromJson(itemsMap, depth: depth + 1);
    } else if (itemType == 'array') {
      itemSchema = ArrayTypeSchema._fromJson(itemsMap, depth: depth + 1);
    }

    return ArrayTypeSchema(itemType: itemType, itemSchema: itemSchema);
  }

  @override
  String toDisplayString() {
    if (itemSchema is ArrayTypeSchema) {
      return 'array<${itemSchema!.toDisplayString()}>';
    }
    return 'array<$itemType>';
  }
}

/// 属性 Schema（用于 ObjectTypeSchema 的每个属性）
class PropertySchema {
  final String type;
  final String? description;
  final TypeSchema? schema; // 如果 type 是 object 或 array，递归定义

  const PropertySchema({
    required this.type,
    this.description,
    this.schema,
  });

  void validate({int depth = 0}) {
    if (!IODefinition.supportedTypes.contains(type)) {
      throw FormatException('属性类型不支持: $type');
    }
    if (type == 'object' && schema == null) {
      throw const FormatException('object 类型的属性必须定义 schema');
    }
    if (type == 'array' && schema == null) {
      throw const FormatException('array 类型的属性必须定义 items');
    }
    schema?.validate(depth: depth);
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'type': type};
    if (description != null) {
      result['description'] = description;
    }
    if (schema != null) {
      if (schema is ObjectTypeSchema) {
        result.addAll(schema!.toJson());
      } else if (schema is ArrayTypeSchema) {
        final arraySchema = schema as ArrayTypeSchema;
        result['items'] = arraySchema.toJson();
      }
    }
    return result;
  }

  factory PropertySchema.fromJson(Map<String, dynamic> json,
      {int depth = 0}) {
    final type = (json['type'] ?? '').toString();
    if (type.isEmpty) {
      throw const FormatException('属性缺少 type 字段');
    }

    TypeSchema? schema;
    if (type == 'object') {
      schema = ObjectTypeSchema._fromJson(json, depth: depth + 1);
    } else if (type == 'array') {
      schema = ArrayTypeSchema._fromJson(json, depth: depth + 1);
    }

    return PropertySchema(
      type: type,
      description: json['description']?.toString(),
      schema: schema,
    );
  }
}

// ─── 默认值类型校验 ──────────────────────────────────────────────

/// 校验默认值是否与声明的类型匹配
bool _isDefaultValueTypeValid(String type, dynamic value) {
  if (value == null) return true; // null 对所有类型都合法
  return switch (type) {
    'string' => value is String,
    'number' => value is num,
    'boolean' => value is bool,
    'object' => value is Map,
    'array' => value is List,
    _ => false,
  };
}

/// 输入输出定义
class IODefinition {
  final String name;
  final String type; // string, number, boolean, object, array
  final String description;
  final bool required;
  final bool isInput; // true = input, false = output
  final dynamic defaultValue; // 默认值（仅 input 有效）
  final bool hasDefault; // 是否提供了 default 字段
  final TypeSchema? schema; // object 类型的 JSON Schema
  final TypeSchema? items; // array 类型的元素类型定义（ArrayTypeSchema）

  IODefinition({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.isInput = false,
    this.defaultValue,
    this.hasDefault = false,
    this.schema,
    this.items,
  });

  static const List<String> supportedTypes = [
    'string',
    'number',
    'boolean',
    'object',
    'array',
  ];

  void validate() {
    if (name.trim().isEmpty) {
      throw const FormatException('IO 定义的 name 不能为空');
    }
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
      throw FormatException(
          'IO 定义的 name "$name" 格式无效，必须以字母或下划线开头，后续为字母、数字、下划线');
    }
    if (!supportedTypes.contains(type)) {
      throw FormatException(
          '不支持的 IO 类型: $type，支持: ${supportedTypes.join(', ')}');
    }

    // object 类型必须有 schema
    if (type == 'object') {
      if (schema == null) {
        throw FormatException('$name: object 类型必须定义 schema');
      }
      if (schema is! ObjectTypeSchema) {
        throw FormatException('$name: object 类型的 schema 格式无效');
      }
      schema!.validate();
    }

    // array 类型必须有 items
    if (type == 'array') {
      if (items == null) {
        throw FormatException('$name: array 类型必须定义 items');
      }
      if (items is! ArrayTypeSchema) {
        throw FormatException('$name: array 类型的 items 格式无效');
      }
      items!.validate();
    }

    // input 必须有默认值
    if (isInput) {
      if (!hasDefault) {
        throw FormatException('$name: input 必须定义 default 字段');
      }
      // 校验默认值类型
      if (defaultValue != null && !_isDefaultValueTypeValid(type, defaultValue)) {
        throw FormatException(
            '$name: default 值类型不匹配，期望 $type，实际为 ${defaultValue.runtimeType}');
      }
    }
  }

  /// 获取详细类型描述字符串（用于 UI 显示）
  String get typeDisplayString {
    if (type == 'object' && schema is ObjectTypeSchema) {
      return (schema as ObjectTypeSchema).toDisplayString();
    }
    if (type == 'array' && items is ArrayTypeSchema) {
      return (items as ArrayTypeSchema).toDisplayString();
    }
    return type;
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'name': name,
      'type': type,
      'description': description,
      'required': required,
    };
    if (isInput && hasDefault) {
      result['default'] = defaultValue;
    }
    if (type == 'object' && schema != null) {
      result['schema'] = schema!.toJson();
    }
    if (type == 'array' && items != null) {
      result['items'] = (items as ArrayTypeSchema).toJson();
    }
    return result;
  }

  factory IODefinition.fromJson(Map<String, dynamic> json,
      {bool isInput = false}) {
    final type = (json['type'] ?? 'string').toString();

    // 解析 schema（仅 object 类型）
    TypeSchema? schema;
    if (type == 'object') {
      final schemaRaw = json['schema'];
      if (schemaRaw is Map) {
        schema = ObjectTypeSchema._fromJson(
            Map<String, dynamic>.from(schemaRaw));
      }
    }

    // 解析 items（仅 array 类型）
    TypeSchema? items;
    if (type == 'array') {
      final itemsRaw = json['items'];
      if (itemsRaw is Map) {
        items = ArrayTypeSchema._fromJson(
            Map<String, dynamic>.from({'items': itemsRaw}));
      }
    }

    // 解析 default
    final hasDefault = json.containsKey('default');
    final defaultValue = hasDefault ? json['default'] : null;

    final def = IODefinition(
      name: (json['name'] ?? '').toString(),
      type: type,
      description: (json['description'] ?? '').toString(),
      required: json['required'] == true,
      isInput: isInput,
      defaultValue: defaultValue,
      hasDefault: hasDefault,
      schema: schema,
      items: items,
    );
    def.validate();
    return def;
  }

  factory IODefinition.fromYaml(dynamic yaml, {bool isInput = false}) {
    if (yaml is! Map) {
      throw const FormatException('IO 定义必须是对象');
    }
    return IODefinition.fromJson(Map<String, dynamic>.from(yaml),
        isInput: isInput);
  }
}
