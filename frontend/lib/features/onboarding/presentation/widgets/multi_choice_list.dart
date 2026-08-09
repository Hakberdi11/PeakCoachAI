import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'choice_option.dart';

class MultiChoiceList extends StatelessWidget {
  const MultiChoiceList({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ChoiceOption> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options.map((option) {
        final isSelected = selected.contains(option.value);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final next = List<String>.from(selected);
            isSelected ? next.remove(option.value) : next.add(option.value);
            onChanged(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primaryAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Text(option.label, style: AppTextStyles.body),
          ),
        );
      }).toList(),
    );
  }
}
