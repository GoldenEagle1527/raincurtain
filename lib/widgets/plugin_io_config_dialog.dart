import 'package:flutter/material.dart';
import '../models/io_definition.dart';
import '../models/pool_plugin.dart';
import '../models/plugin_manager.dart';
import '../models/variable_pool_manager.dart';

/// 插件 localStorage ↔ 变量池 映射配置对话框
///
/// localStorage key 固定来自 manifest inputs/outputs 的 name，只读显示。
/// 用户只能为每个接口填写对应的变量池变量名（留空表示不映射）。
class PluginIOConfigDialog extends StatefulWidget {
  final PoolPlugin poolPlugin;
  final LocalPlugin plugin;
  final String poolId;
  final VariablePoolManager variablePoolManager;

  const PluginIOConfigDialog({
    super.key,
    required this.poolPlugin,
    required this.plugin,
    required this.poolId,
    required this.variablePoolManager,
  });

  @override
  State<PluginIOConfigDialog> createState() => _PluginIOConfigDialogState();
}

class _PluginIOConfigDialogState extends State<PluginIOConfigDialog> {
  // name → TextEditingController (变量池变量名)
  late final Map<String, TextEditingController> _inputControllers;
  late final Map<String, TextEditingController> _outputControllers;
  List<IODefinition> get _inputs => widget.plugin.manifest.inputs;
  List<IODefinition> get _outputs => widget.plugin.manifest.outputs;

  @override
  void initState() {
    super.initState();

    _inputControllers = {
      for (final io in _inputs)
        io.name: TextEditingController(
          text: widget.poolPlugin.inputMappings[io.name] ?? '',
        ),
    };

    _outputControllers = {
      for (final io in _outputs)
        io.name: TextEditingController(
          text: widget.poolPlugin.outputMappings[io.name] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _inputControllers.values) {
      c.dispose();
    }
    for (final c in _outputControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectMappings(
      Map<String, TextEditingController> controllers) {
    final result = <String, String>{};
    for (final entry in controllers.entries) {
      final val = entry.value.text.trim();
      if (val.isNotEmpty) {
        result[entry.key] = val;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasInputs = _inputs.isNotEmpty;
    final hasOutputs = _outputs.isNotEmpty;

    return AlertDialog(
      title: Text('配置 ${widget.plugin.manifest.name}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 说明条
              if (hasInputs && hasOutputs)
                _InfoBanner(
                  text: '输入接口留空则使用插件原有数据；输出接口留空则不映射。',
                )
              else if (hasInputs)
                _InfoBanner(
                  text: '输入接口留空则使用插件原有数据，不从变量池读取。',
                )
              else if (hasOutputs)
                _InfoBanner(
                  text: '为输出接口选择对应的变量池变量名，留空则不映射。',
                ),
              if (hasInputs || hasOutputs) const SizedBox(height: 16),

              // 无接口定义
              if (!hasInputs && !hasOutputs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '该插件未在 manifest.yml 中声明任何输入输出接口',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // 输入映射
              if (hasInputs) ...[
                _SectionHeader(
                  icon: Icons.download_outlined,
                  label: '输入映射（读）',
                  tooltip:
                      '插件通过 storage.get(key) 读取数据时，\n若 key 已映射变量，则优先从变量池获取值',
                ),
                const SizedBox(height: 8),
                _buildTable(
                  context,
                  defs: _inputs,
                  controllers: _inputControllers,
                  colorScheme: colorScheme,
                  isInput: true,
                ),
              ],

              if (hasInputs && hasOutputs) const SizedBox(height: 20),

              // 输出映射
              if (hasOutputs) ...[
                _SectionHeader(
                  icon: Icons.upload_outlined,
                  label: '输出映射（写）',
                  tooltip:
                      '插件调用 storage.set(key, value) 时，\n若 key 已映射变量，则仅写入变量池（不写本地存储）',
                ),
                const SizedBox(height: 8),
                _buildTable(
                  context,
                  defs: _outputs,
                  controllers: _outputControllers,
                  colorScheme: colorScheme,
                  isInput: false,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, (
              inputMappings: _collectMappings(_inputControllers),
              outputMappings: _collectMappings(_outputControllers),
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildTable(
    BuildContext context, {
    required List<IODefinition> defs,
    required Map<String, TextEditingController> controllers,
    required ColorScheme colorScheme,
    required bool isInput,
  }) {
    return Column(
      children: [
        // 列头
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  '接口名',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Text(
                  '变量池变量名',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
        // 每行
        ...defs.map((io) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 左侧：只读接口名 + 类型 + required
                  Expanded(
                    flex: 5,
                    child: _IOKeyCell(io: io, colorScheme: colorScheme),
                  ),
                  const SizedBox(width: 12),
                  // 右侧：可编辑变量名
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: controllers[io.name],
                      decoration: InputDecoration(
                        hintText: isInput ? '变量名（留空则用原有数据）' : '变量名（留空不映射）',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

// ── 只读接口名单元格 ──────────────────────────────────────────────

class _IOKeyCell extends StatelessWidget {
  final IODefinition io;
  final ColorScheme colorScheme;

  const _IOKeyCell({required this.io, required this.colorScheme});

  String _formatDefaultValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) {
      final display = value.length > 30 ? '${value.substring(0, 30)}...' : value;
      return '"$display"';
    }
    final str = value.toString();
    return str.length > 40 ? '${str.substring(0, 40)}...' : str;
  }

  /// 构建 Schema 详情的 tooltip 文本
  String? _buildSchemaTooltip() {
    final lines = <String>[];
    if (io.type == 'object' && io.schema != null) {
      final objSchema = io.schema as ObjectTypeSchema;
      lines.add('properties:');
      for (final entry in objSchema.properties.entries) {
        final req = objSchema.required.contains(entry.key) ? ' *' : '';
        lines.add('  ${entry.key}: ${entry.value.type}$req');
        if (entry.value.description != null) {
          lines.add('    # ${entry.value.description}');
        }
      }
    }
    if (io.type == 'array' && io.items != null) {
      final arrSchema = io.items as ArrayTypeSchema;
      lines.add('items: ${arrSchema.itemType}');
      if (arrSchema.itemSchema is ObjectTypeSchema) {
        final objSchema = arrSchema.itemSchema as ObjectTypeSchema;
        lines.add('  properties:');
        for (final entry in objSchema.properties.entries) {
          final req = objSchema.required.contains(entry.key) ? ' *' : '';
          lines.add('    ${entry.key}: ${entry.value.type}$req');
        }
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final schemaTooltip = _buildSchemaTooltip();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                io.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (io.required) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            _TypeChip(io: io, colorScheme: colorScheme),
            if (schemaTooltip != null) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: schemaTooltip,
                child: Icon(Icons.info_outline,
                    size: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (io.description.isNotEmpty) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  io.description,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        // 默认值展示（仅 input 且有默认值时）
        if (io.isInput && io.hasDefault) ...[
          const SizedBox(height: 2),
          Text(
            '默认: ${_formatDefaultValue(io.defaultValue)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final IODefinition io;
  final ColorScheme colorScheme;

  const _TypeChip({required this.io, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        io.typeDisplayString,
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ── 辅助组件 ─────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final String text;
  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 4),
        Tooltip(
          message: tooltip,
          child: Icon(Icons.help_outline,
              size: 14, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
