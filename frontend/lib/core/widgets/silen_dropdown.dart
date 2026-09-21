import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Design-system select control used when a compact pill is not wide enough.
///
/// Flutter's stock [DropdownButtonFormField] inherits Material's outlined
/// form-field treatment, which does not match SilaFit's soft inset controls.
class SilenDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  const SilenDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label.toUpperCase(),
                    style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant, fontSize: 10)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    dropdownColor: AppColors.surfaceContainerHigh,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.accent),
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurface),
                    items: items,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
