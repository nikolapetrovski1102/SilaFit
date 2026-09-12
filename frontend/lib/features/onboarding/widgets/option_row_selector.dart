import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The selectable-row pattern shared by the gender and goal questions: flat
/// unselected rows, a lime-outlined + checkmark selected row, all animated.
///
/// [options] carries the values [onSelected] fires (and [selected] is
/// compared against) - typically the backend's canonical enum strings.
/// [labelFor] maps each value to the text a row actually displays, so a
/// value like `MaintainActive` can render as "Maintain and stay active"
/// without the widget needing to know about display copy. Defaults to
/// showing the value verbatim (fine when the two already match, as with
/// gender's Male/Female/Other).
class OptionRowSelector extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String Function(String value)? labelFor;

  const OptionRowSelector(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected,
      this.labelFor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options) ...[
          _OptionRow(
            label: labelFor?.call(option) ?? option,
            selected: option == selected,
            onTap: () => onSelected(option),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withOpacity(0.12)
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppTypography.headlineSm.copyWith(fontSize: 17)),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: selected ? 1 : 0,
              child: Icon(Icons.check, color: AppColors.accent, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
