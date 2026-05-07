/// 变量
class Variable {
  final String name;
  final String type;
  final dynamic value;
  final DateTime updatedAt;
  final String? sourcePluginId;

  Variable({
    required this.name,
    required this.type,
    required this.value,
    DateTime? updatedAt,
    this.sourcePluginId,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Variable copyWith({
    dynamic value,
    String? type,
    DateTime? updatedAt,
    String? sourcePluginId,
  }) {
    return Variable(
      name: name,
      type: type ?? this.type,
      value: value ?? this.value,
      updatedAt: updatedAt ?? DateTime.now(),
      sourcePluginId: sourcePluginId ?? this.sourcePluginId,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'value': value,
        'updatedAt': updatedAt.toIso8601String(),
        'sourcePluginId': sourcePluginId,
      };

  factory Variable.fromJson(Map<String, dynamic> json) {
    return Variable(
      name: json['name'] as String,
      type: json['type'] as String,
      value: json['value'],
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sourcePluginId: json['sourcePluginId'] as String?,
    );
  }
}
