import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'choice_option.dart';

class SingleChoiceList extends StatelessWidget {
  const SingleChoiceList({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ChoiceOption> options;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options.map((option) {
        final isSelected = option.value == selected;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onChanged(option.value),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.primaryAccent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(option.label, style: AppTextStyles.body)),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: AppColors.primaryAccent),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
