import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// Simple, accessible answer rows shared by onboarding questions.
/// Labels can wrap at larger text sizes; the entire row is interactive.
///
/// [options] carries the values [onSelected] fires (and [selected] is
/// compared against) - typically the backend's canonical enum strings.
/// [labelFor] maps each value to the text a tile actually displays.
/// [iconFor] maps each value to a Material icon shown at the leading edge.
class OptionRowSelector extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String Function(String value)? labelFor;
  final IconData? Function(String value)? iconFor;

  const OptionRowSelector(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected,
      this.labelFor,
      this.iconFor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in options) ...[
          _OptionTile(
            label: labelFor?.call(option) ?? option,
            icon: iconFor?.call(option),
            selected: option == selected,
            onTap: () => onSelected(option),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile(
      {required this.label,
      this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.10)
            : AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(children: [
                if (icon != null) ...[
                  ExcludeSemantics(
                      child: Icon(icon,
                          size: 26,
                          color: selected
                              ? AppColors.accent
                              : AppColors.onSurfaceVariant)),
                  const SizedBox(width: 16),
                ],
                Expanded(
                    child: Text(label,
                        style:
                            AppTypography.headlineSm.copyWith(fontSize: 16))),
                const SizedBox(width: 12),
                ExcludeSemantics(
                    child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 24,
                  color: selected ? AppColors.accent : AppColors.outlineVariant,
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
