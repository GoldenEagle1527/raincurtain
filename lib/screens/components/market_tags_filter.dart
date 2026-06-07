import 'package:flutter/material.dart';

class MarketTagsFilter extends StatelessWidget {
  final List<String> tags;
  final String selectedTag;
  final void Function(String tag) onTagSelected;

  const MarketTagsFilter({
    super.key,
    required this.tags,
    required this.selectedTag,
    required this.onTagSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: selectedTag.isEmpty,
            onSelected: (selected) {
              onTagSelected('');
            },
          ),
          const SizedBox(width: 8),
          ...tags.map((tag) {
            final isSelected = selectedTag == tag;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(tag),
                selected: isSelected,
                onSelected: (selected) {
                  onTagSelected(selected ? tag : '');
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
