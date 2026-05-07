import 'package:uuid/uuid.dart';

/// 池内插件配置
class PoolPlugin {
  final String id;
  final String pluginId;
  final int order;
  final Map<String, String> inputMappings; // {inputName: variableName}
  final Map<String, String> outputMappings; // {outputName: variableName}

  PoolPlugin({
    String? id,
    required this.pluginId,
    required this.order,
    Map<String, String>? inputMappings,
    Map<String, String>? outputMappings,
  })  : id = id ?? const Uuid().v7(),
        inputMappings = inputMappings ?? {},
        outputMappings = outputMappings ?? {};

  PoolPlugin copyWith({
    int? order,
    Map<String, String>? inputMappings,
    Map<String, String>? outputMappings,
  }) {
    return PoolPlugin(
      id: id,
      pluginId: pluginId,
      order: order ?? this.order,
      inputMappings: inputMappings ?? Map.from(this.inputMappings),
      outputMappings: outputMappings ?? Map.from(this.outputMappings),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pluginId': pluginId,
        'order': order,
        'inputMappings': inputMappings,
        'outputMappings': outputMappings,
      };

  factory PoolPlugin.fromJson(Map<String, dynamic> json) {
    return PoolPlugin(
      id: json['id'] as String,
      pluginId: json['pluginId'] as String,
      order: json['order'] as int,
      inputMappings: Map<String, String>.from(
          (json['inputMappings'] as Map?) ?? {}),
      outputMappings: Map<String, String>.from(
          (json['outputMappings'] as Map?) ?? {}),
    );
  }
}
