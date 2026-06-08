import 'package:flutter/material.dart';

class MarketTagsFilter extends StatelessWidget {
  final List<String> tags;
  final Set<String> selectedTags;
  final void Function(Set<String> selectedTags) onTagsChanged;
  final bool showReset;
  final VoidCallback? onClear;

  const MarketTagsFilter({
    super.key,
    required this.tags,
    required this.selectedTags,
    required this.onTagsChanged,
    required this.showReset,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty && !showReset) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '筛选：',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (showReset) ...[
                  InputChip(
                    avatar: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    label: Text(
                      '重置',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: onClear,
                    backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.15),
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                FilterChip(
                  label: const Text('全部'),
                  selected: selectedTags.isEmpty,
                  onSelected: (selected) {
                    if (selected) {
                      onTagsChanged({});
                    }
                  },
                ),
                const SizedBox(width: 8),
                ...tags.map((tag) {
                  final isSelected = selectedTags.contains(tag);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (selected) {
                        final newTags = Set<String>.from(selectedTags);
                        if (selected) {
                          newTags.add(tag);
                        } else {
                          newTags.remove(tag);
                        }
                        onTagsChanged(newTags);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
