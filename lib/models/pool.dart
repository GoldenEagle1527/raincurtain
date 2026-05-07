import 'package:uuid/uuid.dart';

/// 池（Pool）数据模型
class Pool {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Pool({
    String? id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v7(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Pool copyWith({
    String? name,
    DateTime? updatedAt,
  }) {
    return Pool(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Pool.fromJson(Map<String, dynamic> json) {
    return Pool(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
