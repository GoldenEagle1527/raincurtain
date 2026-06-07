import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/pool_manager.dart';

class CreatePoolDialog extends StatefulWidget {
  const CreatePoolDialog({super.key});

  @override
  State<CreatePoolDialog> createState() => _CreatePoolDialogState();
}

class _CreatePoolDialogState extends State<CreatePoolDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建池'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '池名称',
          hintText: '请输入池的名称',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) {
              context.read<PoolManager>().createPool(name);
              Navigator.pop(context);
            }
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
